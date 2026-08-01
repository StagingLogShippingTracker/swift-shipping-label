import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Result of attempting to download a customer logo from the web.
class LogoFindResult {
  const LogoFindResult.ok(this.bytes, {required this.source, this.hint = ''})
      : error = null;

  const LogoFindResult.fail(this.error)
      : bytes = null,
        source = '',
        hint = '';

  final Uint8List? bytes;
  final String source;
  final String hint;
  final String? error;

  bool get ok => bytes != null && bytes!.isNotEmpty && error == null;
}

/// Best-effort HD logo lookup without brittle Google Images scraping.
///
/// Tries (in order): Clearbit Logo API by domain, Wikipedia page image,
/// DuckDuckGo Instant Answer image, then a larger Google favicon as last resort.
class LogoFinder {
  LogoFinder({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const maxBytes = 5 * 1024 * 1024;
  static const _ua = 'SwiftShippingLabel/1.0 (+https://github.com/StagingLogShippingTracker/swift-shipping-label)';

  Future<LogoFindResult> find({
    required String companyName,
    String domain = '',
  }) async {
    final name = companyName.trim();
    final dom = _normalizeDomain(domain);
    if (name.isEmpty && dom.isEmpty) {
      return const LogoFindResult.fail(
        'Enter a customer name or website domain to search.',
      );
    }

    final domains = <String>[
      if (dom.isNotEmpty) dom,
      ..._guessDomains(name),
    ];
    // Unique preserve order
    final seen = <String>{};
    final domainList = [
      for (final d in domains)
        if (d.isNotEmpty && seen.add(d)) d,
    ];

    for (final d in domainList) {
      final clearbit = await _downloadImage(
        Uri.parse('https://logo.clearbit.com/$d'),
        source: 'Clearbit ($d)',
      );
      if (clearbit.ok) return clearbit;
    }

    if (name.isNotEmpty) {
      final wiki = await _wikipediaLogo(name);
      if (wiki.ok) return wiki;

      final ddg = await _duckDuckGoImage('$name logo');
      if (ddg.ok) return ddg;
    }

    for (final d in domainList.take(3)) {
      final fav = await _downloadImage(
        Uri.parse('https://www.google.com/s2/favicons?sz=256&domain_url=$d'),
        source: 'Favicon ($d)',
        minBytes: 800,
      );
      if (fav.ok) {
        return LogoFindResult.ok(
          fav.bytes!,
          source: fav.source,
          hint: 'Low-resolution favicon — upload a better logo if needed.',
        );
      }
    }

    return LogoFindResult.fail(
      name.isEmpty
          ? 'No logo found for that domain. Try another domain or upload manually.'
          : 'No usable logo found for “$name”. Try a website domain or upload manually.',
    );
  }

  Future<LogoFindResult> _wikipediaLogo(String name) async {
    try {
      final searchUri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': name,
        'srlimit': '3',
        'format': 'json',
        'origin': '*',
      });
      final searchRes = await _client
          .get(searchUri, headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 12));
      if (searchRes.statusCode != 200) {
        return const LogoFindResult.fail('Wikipedia search failed.');
      }
      final body = jsonDecode(searchRes.body);
      final hits = body['query']?['search'];
      if (hits is! List || hits.isEmpty) {
        return const LogoFindResult.fail('No Wikipedia match.');
      }

      for (final hit in hits.take(3)) {
        final title = '${hit['title'] ?? ''}';
        if (title.isEmpty) continue;
        final imgUri = Uri.https('en.wikipedia.org', '/w/api.php', {
          'action': 'query',
          'titles': title,
          'prop': 'pageimages',
          'pithumbsize': '1200',
          'piprop': 'thumbnail',
          'format': 'json',
          'origin': '*',
        });
        final imgRes = await _client
            .get(imgUri, headers: {'User-Agent': _ua})
            .timeout(const Duration(seconds: 12));
        if (imgRes.statusCode != 200) continue;
        final imgBody = jsonDecode(imgRes.body);
        final pages = imgBody['query']?['pages'];
        if (pages is! Map) continue;
        for (final page in pages.values) {
          final thumb = page is Map ? page['thumbnail'] : null;
          final src = thumb is Map ? '${thumb['source'] ?? ''}' : '';
          if (src.isEmpty) continue;
          final dl = await _downloadImage(
            Uri.parse(src),
            source: 'Wikipedia ($title)',
          );
          if (dl.ok) return dl;
        }
      }
    } catch (_) {
      return const LogoFindResult.fail('Wikipedia lookup failed.');
    }
    return const LogoFindResult.fail('No Wikipedia logo image.');
  }

  Future<LogoFindResult> _duckDuckGoImage(String query) async {
    try {
      final uri = Uri.https('api.duckduckgo.com', '/', {
        'q': query,
        'format': 'json',
        'pretty': '0',
        'no_redirect': '1',
        'no_html': '1',
      });
      final res = await _client
          .get(uri, headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        return const LogoFindResult.fail('DuckDuckGo lookup failed.');
      }
      final body = jsonDecode(res.body);
      final image = '${body['Image'] ?? ''}';
      if (image.isEmpty) {
        // RelatedTopics sometimes carry Icon.URL
        final related = body['RelatedTopics'];
        if (related is List) {
          for (final item in related.take(8)) {
            if (item is! Map) continue;
            final icon = item['Icon'];
            final url = icon is Map ? '${icon['URL'] ?? ''}' : '';
            if (url.startsWith('http')) {
              final dl = await _downloadImage(
                Uri.parse(url),
                source: 'DuckDuckGo',
                minBytes: 400,
              );
              if (dl.ok) return dl;
            }
          }
        }
        return const LogoFindResult.fail('No DuckDuckGo image.');
      }
      final imgUrl = image.startsWith('http')
          ? image
          : 'https://duckduckgo.com$image';
      return _downloadImage(Uri.parse(imgUrl), source: 'DuckDuckGo');
    } catch (_) {
      return const LogoFindResult.fail('DuckDuckGo lookup failed.');
    }
  }

  Future<LogoFindResult> _downloadImage(
    Uri uri, {
    required String source,
    int minBytes = 1200,
  }) async {
    try {
      final res = await _client
          .get(uri, headers: {'User-Agent': _ua, 'Accept': 'image/*,*/*'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return LogoFindResult.fail('HTTP ${res.statusCode} from $source');
      }
      final bytes = res.bodyBytes;
      if (bytes.length > maxBytes) {
        return const LogoFindResult.fail('Image too large (over 5 MB).');
      }
      if (bytes.length < minBytes) {
        return LogoFindResult.fail('Image from $source too small.');
      }
      if (!_looksLikeImage(bytes)) {
        return LogoFindResult.fail('Response from $source was not an image.');
      }
      return LogoFindResult.ok(Uint8List.fromList(bytes), source: source);
    } catch (e) {
      return LogoFindResult.fail('Network error ($source): $e');
    }
  }

  static bool _looksLikeImage(List<int> b) {
    if (b.length < 8) return false;
    // PNG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true;
    }
    // JPEG
    if (b[0] == 0xFF && b[1] == 0xD8) return true;
    // GIF
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true;
    // WEBP (RIFF....WEBP)
    if (b.length > 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return true;
    }
    // ICO
    if (b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x01 && b[3] == 0x00) {
      return true;
    }
    return false;
  }

  static String _normalizeDomain(String raw) {
    var d = raw.trim().toLowerCase();
    if (d.isEmpty) return '';
    d = d.replaceAll(RegExp(r'^https?://'), '');
    d = d.replaceAll(RegExp(r'^www\.'), '');
    d = d.split('/').first.split('?').first.trim();
    d = d.replaceAll(RegExp(r'[^a-z0-9.\-]'), '');
    if (!d.contains('.') || d.startsWith('.') || d.endsWith('.')) return '';
    return d;
  }

  static List<String> _guessDomains(String companyName) {
    final cleaned = companyName
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'\b(inc|incorporated|ltd|limited|llc|corp|corporation|co|company|plc|lp|partnership|the)\b',
          ),
          '',
        )
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return const [];
    final compact = cleaned.replaceAll(' ', '');
    final dashed = cleaned.replaceAll(' ', '-');
    final out = <String>{
      '$compact.com',
      '$dashed.com',
      '$compact.ca',
      '$dashed.ca',
      '$compact.net',
    };
    // Single-token only for shorter guesses
    final words = cleaned.split(' ');
    if (words.length >= 2) {
      out.add('${words.first}${words[1]}.com');
      out.add('${words.first}.com');
    }
    return out.toList();
  }

  static String extensionForBytes(Uint8List bytes) {
    if (_looksLikeImage(bytes)) {
      if (bytes[0] == 0x89) return '.png';
      if (bytes[0] == 0xFF) return '.jpg';
      if (bytes[0] == 0x47) return '.gif';
      if (bytes[0] == 0x52) return '.webp';
      if (bytes[0] == 0x00) return '.ico';
    }
    return '.png';
  }
}
