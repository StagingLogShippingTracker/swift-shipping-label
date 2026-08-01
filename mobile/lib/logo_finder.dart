import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A logo image URL discovered from a web source, ranked for download.
class LogoCandidate {
  const LogoCandidate({
    required this.url,
    required this.source,
    required this.score,
  });

  final String url;
  final String source;
  final int score;
}

/// A successfully downloaded logo candidate ready for the picker UI.
class LogoDownloadedCandidate {
  const LogoDownloadedCandidate({
    required this.bytes,
    required this.source,
    required this.url,
    required this.score,
    this.hint = '',
  });

  final Uint8List bytes;
  final String source;
  final String url;
  final int score;
  final String hint;
}

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

/// Multi-source logo lookup: image search (Google, Bing), logo libraries
/// (Brands of the World, Logo.dev, Brandfetch), plus Clearbit / Wikipedia fallbacks.
class LogoFinder {
  LogoFinder({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const maxBytes = 5 * 1024 * 1024;
  static const _maxCandidatesToDownload = 10;
  static const _ua =
      'SwiftShippingLabel/1.0 (+https://github.com/StagingLogShippingTracker/swift-shipping-label)';
  static const _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static Map<String, String> get _browserHeaders => {
        'User-Agent': _browserUa,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      };

  /// Returns ranked, successfully downloaded logo candidates from all sources.
  Future<List<LogoDownloadedCandidate>> findDownloadedCandidates({
    required String companyName,
    String domain = '',
  }) async {
    final name = companyName.trim();
    final dom = _normalizeDomain(domain);
    if (name.isEmpty && dom.isEmpty) return const [];

    final domainList = _uniqueDomains(name, dom);
    final downloaded = <LogoDownloadedCandidate>[];

    // Fast domain-based lookups first.
    for (final d in domainList) {
      final clearbit = await _downloadImage(
        Uri.parse('https://logo.clearbit.com/$d'),
        source: 'Clearbit ($d)',
      );
      if (clearbit.ok) {
        downloaded.add(
          LogoDownloadedCandidate(
            bytes: clearbit.bytes!,
            source: clearbit.source,
            url: 'https://logo.clearbit.com/$d',
            score: 100,
          ),
        );
      }
    }

    for (final c in _logoDevCandidates(domainList)) {
      final dl = await _downloadImage(Uri.parse(c.url), source: c.source);
      if (dl.ok) {
        downloaded.add(
          LogoDownloadedCandidate(
            bytes: dl.bytes!,
            source: dl.source,
            url: c.url,
            score: c.score,
          ),
        );
      }
    }

    for (final c in _brandfetchCandidates(domainList)) {
      final dl = await _downloadImage(Uri.parse(c.url), source: c.source);
      if (dl.ok) {
        downloaded.add(
          LogoDownloadedCandidate(
            bytes: dl.bytes!,
            source: dl.source,
            url: c.url,
            score: c.score,
          ),
        );
      }
    }

    if (downloaded.isNotEmpty) {
      downloaded.sort((a, b) => b.score.compareTo(a.score));
      return downloaded;
    }

    // Broader logo-focused image / library search.
    final query = name.isEmpty ? 'logo' : '$name logo';
    final urlCandidates = await _searchAllSources(
      query: query,
      companyName: name,
      domains: domainList,
    );

    for (final c in urlCandidates.take(_maxCandidatesToDownload)) {
      final dl = await _downloadImage(Uri.parse(c.url), source: c.source);
      if (dl.ok) {
        downloaded.add(
          LogoDownloadedCandidate(
            bytes: dl.bytes!,
            source: dl.source,
            url: c.url,
            score: c.score,
            hint: '',
          ),
        );
      }
    }

    if (downloaded.isNotEmpty) {
      downloaded.sort((a, b) => b.score.compareTo(a.score));
      return downloaded;
    }

    // Legacy fallbacks.
    if (name.isNotEmpty) {
      final wiki = await _wikipediaLogo(name);
      if (wiki.ok) {
        return [
          LogoDownloadedCandidate(
            bytes: wiki.bytes!,
            source: wiki.source,
            url: '',
            score: 40,
          ),
        ];
      }

      final ddg = await _duckDuckGoImage(query);
      if (ddg.ok) {
        return [
          LogoDownloadedCandidate(
            bytes: ddg.bytes!,
            source: ddg.source,
            url: '',
            score: 30,
          ),
        ];
      }
    }

    for (final d in domainList.take(3)) {
      final fav = await _downloadImage(
        Uri.parse('https://www.google.com/s2/favicons?sz=256&domain_url=$d'),
        source: 'Favicon ($d)',
        minBytes: 800,
      );
      if (fav.ok) {
        return [
          LogoDownloadedCandidate(
            bytes: fav.bytes!,
            source: fav.source,
            url: '',
            score: 10,
            hint: 'Low-resolution favicon — upload a better logo if needed.',
          ),
        ];
      }
    }

    return const [];
  }

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

    final candidates = await findDownloadedCandidates(
      companyName: name,
      domain: dom,
    );
    if (candidates.isEmpty) {
      return LogoFindResult.fail(
        name.isEmpty
            ? 'No logo found for that domain. Try another domain or upload manually.'
            : 'No usable logo found for “$name”. Searched Google, Bing, Brands of the World, and other sources — try a website domain or upload manually.',
      );
    }

    final best = candidates.first;
    return LogoFindResult.ok(
      best.bytes,
      source: best.source,
      hint: best.hint,
    );
  }

  Future<List<LogoCandidate>> _searchAllSources({
    required String query,
    required String companyName,
    required List<String> domains,
  }) async {
    final results = await Future.wait([
      _bingImageSearch(query),
      _googleImageSearch(query),
      if (companyName.isNotEmpty) _brandsOfTheWorldSearch(companyName),
      _tineyeSearch(query),
      Future.value(_logoDevCandidates(domains)),
      Future.value(_brandfetchCandidates(domains)),
    ]);

    final merged = <LogoCandidate>[];
    for (final list in results) {
      merged.addAll(list);
    }
    return _rankAndDedupe(merged);
  }

  List<String> _uniqueDomains(String name, String dom) {
    final domains = <String>[
      if (dom.isNotEmpty) dom,
      ..._guessDomains(name),
    ];
    final seen = <String>{};
    return [
      for (final d in domains)
        if (d.isNotEmpty && seen.add(d)) d,
    ];
  }

  List<LogoCandidate> _logoDevCandidates(List<String> domains) {
    final token = _optionalEnv('LOGO_DEV_TOKEN');
    if (token.isEmpty) return const [];
    return [
      for (final d in domains.take(4))
        LogoCandidate(
          url: 'https://img.logo.dev/$d?token=$token&size=512&format=png',
          source: 'Logo.dev',
          score: 88,
        ),
    ];
  }

  List<LogoCandidate> _brandfetchCandidates(List<String> domains) {
    final clientId = _optionalEnv('BRANDFETCH_CLIENT_ID');
    if (clientId.isEmpty) return const [];
    return [
      for (final d in domains.take(4))
        LogoCandidate(
          url: 'https://cdn.brandfetch.io/$d/w/512/h/512/logo?c=$clientId',
          source: 'Brandfetch',
          score: 86,
        ),
    ];
  }

  static String _optionalEnv(String key) {
    try {
      return Platform.environment[key] ??
          String.fromEnvironment(key, defaultValue: '');
    } catch (_) {
      return String.fromEnvironment(key, defaultValue: '');
    }
  }

  Future<List<LogoCandidate>> _bingImageSearch(String query) async {
    try {
      final encoded = Uri.encodeQueryComponent(query);
      final referer = 'https://www.bing.com/images/search?q=$encoded';
      final headers = {
        ..._browserHeaders,
        'Referer': referer,
      };

      final urls = <String>{};

      final asyncUri = Uri.parse(
        'https://www.bing.com/images/async?q=$encoded&first=0&count=35&relp=35',
      );
      final asyncRes = await _client
          .get(asyncUri, headers: headers)
          .timeout(const Duration(seconds: 14));
      if (asyncRes.statusCode == 200) {
        urls.addAll(_parseBingMurls(asyncRes.body));
      }

      if (urls.length < 5) {
        final pageUri = Uri.parse(
          'https://www.bing.com/images/search?q=$encoded&qft=+filterui:photo-photo',
        );
        final pageRes = await _client
            .get(pageUri, headers: headers)
            .timeout(const Duration(seconds: 14));
        if (pageRes.statusCode == 200) {
          urls.addAll(_parseBingMurls(pageRes.body));
        }
      }

      return [
        for (final url in urls)
          if (_isAcceptableLogoUrl(url))
            LogoCandidate(
              url: url,
              source: 'Bing Images',
              score: _scoreUrl(url, 'Bing Images'),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Iterable<String> _parseBingMurls(String html) sync* {
    for (final pattern in [
      RegExp(r'murl&quot;:&quot;(https?://[^&]+?)&quot;'),
      RegExp(r'"murl":"(https?://[^"]+)"'),
      RegExp(r'murl":"(https?://[^"]+)"'),
    ]) {
      for (final m in pattern.allMatches(html)) {
        final url = m.group(1);
        if (url != null && url.startsWith('http')) yield url;
      }
    }
  }

  Future<List<LogoCandidate>> _googleImageSearch(String query) async {
    // Google Images often requires JavaScript; we parse embedded JSON when present.
    try {
      final uri = Uri.https('www.google.com', '/search', {
        'q': query,
        'tbm': 'isch',
        'hl': 'en',
        'gl': 'us',
        'ijn': '0',
      });
      final res = await _client
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return const [];

      final urls = <String>{};
      final html = res.body;

      for (final pattern in [
        RegExp(r'"ou":"(https?://[^"]+)"'),
        RegExp(r'\\"ou\\":\\"(https?://[^\\"]+)\\"'),
        RegExp(r'imgurl=(https?://[^&"]+)'),
        RegExp(r'"ou":\s*"(https?://[^"]+)"'),
      ]) {
        for (final m in pattern.allMatches(html)) {
          final raw = m.group(1);
          if (raw == null) continue;
          urls.add(Uri.decodeComponent(raw.replaceAll(r'\\/', '/')));
        }
      }

      for (final m
          in RegExp(r'AF_initDataCallback\(\{[^;]+\}\);', dotAll: true)
              .allMatches(html)) {
        _collectOuFields(m.group(0) ?? '', urls);
      }

      return [
        for (final url in urls)
          if (_isAcceptableLogoUrl(url))
            LogoCandidate(
              url: url,
              source: 'Google Images',
              score: _scoreUrl(url, 'Google Images'),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static void _collectOuFields(String chunk, Set<String> urls) {
    for (final m in RegExp(r'"ou":"(https?://[^"]+)"').allMatches(chunk)) {
      final u = m.group(1);
      if (u != null) urls.add(u);
    }
  }

  Future<List<LogoCandidate>> _brandsOfTheWorldSearch(String name) async {
    try {
      final searchUri = Uri.https('www.brandsoftheworld.com', '/search/logo', {
        'search_api_views_fulltext': name,
      });
      final res = await _client
          .get(searchUri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return const [];

      final html = res.body;
      final urls = <String>{};
      final nameLower = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      for (final m in RegExp(
        r'https://d1yjjnpx0p53s8\.cloudfront\.net/styles/[^"''>\s]+',
      ).allMatches(html)) {
        final url = m.group(0)!;
        if (url.contains('logo-botw') || url.contains('aotw-envelope')) continue;
        urls.add(url);
      }

      final slugs = <String>{};
      for (final m
          in RegExp(r'href="(/logo/[^"?]+)"').allMatches(html)) {
        slugs.add(m.group(1)!);
      }

      for (final slug in slugs.take(3)) {
        final detailUri = Uri.parse('https://www.brandsoftheworld.com$slug');
        try {
          final detail = await _client
              .get(detailUri, headers: _browserHeaders)
              .timeout(const Duration(seconds: 10));
          if (detail.statusCode != 200) continue;
          for (final m in RegExp(
            r'https://d1yjjnpx0p53s8\.cloudfront\.net/styles/[^"''>\s]+',
          ).allMatches(detail.body)) {
            final url = m.group(0)!;
            if (!url.contains('aotw-envelope')) urls.add(url);
          }
        } catch (_) {
          continue;
        }
      }

      return [
        for (final url in urls)
          LogoCandidate(
            url: url,
            source: 'Brands of the World',
            score: _scoreUrl(url, 'Brands of the World') +
                (nameLower.isNotEmpty &&
                        url.toLowerCase().contains(nameLower.substring(
                              0,
                              nameLower.length.clamp(0, 6),
                            ))
                    ? 12
                    : 0),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// TinEye is primarily reverse-image search; their text search UI is a JS SPA.
  /// We attempt the public query URL but usually get no parseable candidates.
  Future<List<LogoCandidate>> _tineyeSearch(String query) async {
    try {
      final uri = Uri.https('tineye.com', '/search', {'query': query});
      final res = await _client
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];

      final urls = <String>{};
      for (final m in RegExp(
        r'https?://[^"''>\s]+\.(?:png|jpg|jpeg|webp)(?:[^"''>\s]*)',
      ).allMatches(res.body)) {
        final url = m.group(0)!;
        if (_isAcceptableLogoUrl(url) && !url.contains('tineye.com')) {
          urls.add(url);
        }
      }

      return [
        for (final url in urls)
          LogoCandidate(
            url: url,
            source: 'TinEye',
            score: _scoreUrl(url, 'TinEye'),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static List<LogoCandidate> _rankAndDedupe(List<LogoCandidate> input) {
    final seen = <String>{};
    final out = <LogoCandidate>[];
    for (final c in input) {
      final key = _urlKey(c.url);
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(c);
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  static String _urlKey(String url) {
    try {
      final u = Uri.parse(url);
      return '${u.scheme}://${u.host}${u.path}'.toLowerCase();
    } catch (_) {
      return url.toLowerCase();
    }
  }

  static int _scoreUrl(String url, String source) {
    var score = 0;
    final lower = url.toLowerCase();

    if (lower.contains('.png')) score += 14;
    if (lower.contains('.webp')) score += 8;
    if (lower.contains('.jpg') || lower.contains('.jpeg')) score += 6;
    if (lower.contains('.gif')) score += 2;
    if (lower.contains('logo')) score += 10;
    if (lower.contains('brand')) score += 4;
    if (lower.contains('vector') || lower.contains('svg')) score += 3;

    if (lower.contains('thumb') ||
        lower.contains('thumbnail') ||
        lower.contains('icon') ||
        lower.contains('favicon') ||
        lower.contains('sprite')) {
      score -= 18;
    }
    if (lower.contains('gstatic.com') ||
        lower.contains('googleusercontent.com/imgres') ||
        lower.contains('bing.com/th') ||
        lower.contains('=s16') ||
        lower.contains('=s32') ||
        lower.contains('w=16') ||
        lower.contains('h=16')) {
      score -= 15;
    }
    if (lower.contains('cloudfront.net') && lower.contains('logo')) score += 8;

    switch (source) {
      case 'Brands of the World':
        score += 12;
      case 'Logo.dev':
        score += 14;
      case 'Brandfetch':
        score += 13;
      case 'Bing Images':
        score += 6;
      case 'Google Images':
        score += 5;
      case 'TinEye':
        score += 2;
    }
    return score;
  }

  static bool _isAcceptableLogoUrl(String url) {
    if (!url.startsWith('http')) return false;
    final lower = url.toLowerCase();
    if (lower.endsWith('.svg') || lower.contains('.svg?')) return false;
    if (lower.contains('data:image')) return false;
    if (lower.contains('facebook.com/tr') ||
        lower.contains('doubleclick') ||
        lower.contains('pixel.') ||
        lower.contains('/ads/')) {
      return false;
    }
    return lower.contains('.png') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.webp') ||
        lower.contains('.gif') ||
        lower.contains('logo') ||
        lower.contains('brand') ||
        lower.contains('cloudfront.net');
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
          .get(
            uri,
            headers: {
              'User-Agent': _browserUa,
              'Accept': 'image/*,*/*',
            },
          )
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
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true;
    }
    if (b[0] == 0xFF && b[1] == 0xD8) return true;
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true;
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
