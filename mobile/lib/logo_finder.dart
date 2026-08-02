import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Which web source(s) to query when finding a customer logo.
enum LogoSearchEngine {
  all,
  google,
  bing,
  clearbit,
  brandsOfTheWorld,
  logoDev,
  brandfetch,
  tineye,
  wikipediaDuckDuckGo,
  retoolClearbit;

  static const defaultEngine = LogoSearchEngine.all;

  String get id => name;

  String get label => switch (this) {
        LogoSearchEngine.all => 'All sources',
        LogoSearchEngine.google => 'Google',
        LogoSearchEngine.bing => 'Bing',
        LogoSearchEngine.clearbit => 'Clearbit',
        LogoSearchEngine.brandsOfTheWorld => 'Brands of the World',
        LogoSearchEngine.logoDev => 'Logo.dev',
        LogoSearchEngine.brandfetch => 'Brandfetch',
        LogoSearchEngine.tineye => 'TinEye',
        LogoSearchEngine.wikipediaDuckDuckGo => 'Wikipedia / DuckDuckGo',
        LogoSearchEngine.retoolClearbit => 'Clearbit via Retool',
      };

  static LogoSearchEngine? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final e in LogoSearchEngine.values) {
      if (e.id == raw) return e;
    }
    return null;
  }

  /// UI order: Google & Bing first, then the rest; Retool last when configured.
  static List<LogoSearchEngine> pickerOptions({required bool retoolConfigured}) {
    final out = <LogoSearchEngine>[
      LogoSearchEngine.all,
      LogoSearchEngine.google,
      LogoSearchEngine.bing,
      LogoSearchEngine.clearbit,
      LogoSearchEngine.brandsOfTheWorld,
      LogoSearchEngine.logoDev,
      LogoSearchEngine.brandfetch,
      LogoSearchEngine.tineye,
      LogoSearchEngine.wikipediaDuckDuckGo,
    ];
    if (retoolConfigured) out.add(LogoSearchEngine.retoolClearbit);
    return out;
  }

  static bool retoolClearbitConfigured() =>
      LogoFinder._retoolClearbitUrlTemplate().isNotEmpty;
}

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

class _RelevanceContext {
  const _RelevanceContext({
    required this.companyName,
    required this.domains,
    required this.tokens,
  });

  final String companyName;
  final List<String> domains;
  final List<String> tokens;

  factory _RelevanceContext.from(String companyName, List<String> domains) {
    return _RelevanceContext(
      companyName: companyName.trim(),
      domains: domains,
      tokens: LogoFinder._companyTokens(companyName),
    );
  }
}

/// Multi-source logo lookup: Clearbit, image search (Google, Bing), logo libraries
/// (Brands of the World, Logo.dev, Brandfetch), Wikipedia / DuckDuckGo fallbacks.
class LogoFinder {
  LogoFinder({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const maxBytes = 5 * 1024 * 1024;
  static const _maxCandidatesToDownload = 10;
  static const _minUrlCandidateScore = 28;
  static const _minDownloadedScore = 32;
  static const _pickerMinScore = 40;
  static const _autoPickLead = 14;
  static const _ua =
      'SwiftShippingLabel/1.0 (+https://github.com/StagingLogShippingTracker/swift-shipping-label)';
  static const _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static Map<String, String> get _browserHeaders => {
        'User-Agent': _browserUa,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      };

  /// Filters downloaded candidates for the picker UI — drops low-relevance junk
  /// and auto-selects when one candidate is clearly best.
  static List<LogoDownloadedCandidate> filterForPicker(
    List<LogoDownloadedCandidate> candidates,
  ) {
    if (candidates.isEmpty) return candidates;
    final sorted = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
    final strong =
        sorted.where((c) => c.score >= _pickerMinScore).take(6).toList();
    if (strong.isEmpty) return sorted.take(1).toList();
    if (strong.length == 1) return strong;
    if (strong.first.score >= strong[1].score + _autoPickLead) {
      return strong.take(1).toList();
    }
    return strong;
  }

  /// Returns ranked, successfully downloaded logo candidates from selected sources.
  Future<List<LogoDownloadedCandidate>> findDownloadedCandidates({
    required String companyName,
    String domain = '',
    LogoSearchEngine engine = LogoSearchEngine.all,
  }) async {
    final name = companyName.trim();
    final dom = _normalizeDomain(domain);
    if (name.isEmpty && dom.isEmpty) return const [];

    final domainList = _uniqueDomains(name, dom);
    final ctx = _RelevanceContext.from(name, domainList);
    final query = name.isEmpty ? 'logo' : '$name logo';
    final useAll = engine == LogoSearchEngine.all;
    final use = (LogoSearchEngine e) => useAll || engine == e;

    final futures = <Future<List<LogoCandidate>>>[];
    if (use(LogoSearchEngine.clearbit)) {
      futures.add(Future.value(_clearbitUrlCandidates(domainList, ctx)));
    }
    if (use(LogoSearchEngine.retoolClearbit)) {
      futures.add(_retoolClearbitCandidates(domainList, ctx));
    }
    if (use(LogoSearchEngine.logoDev)) {
      futures.add(Future.value(_logoDevCandidates(domainList, ctx)));
    }
    if (use(LogoSearchEngine.brandfetch)) {
      futures.add(Future.value(_brandfetchCandidates(domainList, ctx)));
    }
    if (use(LogoSearchEngine.bing)) {
      futures.add(_bingImageSearch(query, ctx));
    }
    if (use(LogoSearchEngine.google)) {
      futures.add(_googleImageSearch(query, ctx));
    }
    if (use(LogoSearchEngine.brandsOfTheWorld) && name.isNotEmpty) {
      futures.add(_brandsOfTheWorldSearch(name, ctx));
    }
    if (use(LogoSearchEngine.tineye)) {
      futures.add(_tineyeSearch(query, ctx));
    }
    if (use(LogoSearchEngine.wikipediaDuckDuckGo) && name.isNotEmpty) {
      futures.add(_wikipediaCandidates(name, ctx));
      futures.add(_duckDuckGoCandidates('$name logo', ctx));
    }

    final urlLists = await Future.wait(futures);

    final merged = <LogoCandidate>[];
    for (final list in urlLists) {
      merged.addAll(list);
    }

    final ranked = _rankAndDedupe(merged, ctx);
    final downloaded = <LogoDownloadedCandidate>[];

    for (final c in ranked.take(_maxCandidatesToDownload)) {
      final dl = await _downloadImage(Uri.parse(c.url), source: c.source);
      if (!dl.ok) continue;
      final finalScore = c.score + _bytesBonus(dl.bytes!);
      if (finalScore < _minDownloadedScore) continue;
      downloaded.add(
        LogoDownloadedCandidate(
          bytes: dl.bytes!,
          source: c.source,
          url: c.url,
          score: finalScore,
        ),
      );
    }

    if (downloaded.isNotEmpty) {
      downloaded.sort((a, b) => b.score.compareTo(a.score));
      return downloaded;
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
            score: 12,
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
    LogoSearchEngine engine = LogoSearchEngine.all,
  }) async {
    final name = companyName.trim();
    final dom = _normalizeDomain(domain);
    if (name.isEmpty && dom.isEmpty) {
      return const LogoFindResult.fail(
        'Enter a customer name or website domain to search.',
      );
    }

    final candidates = filterForPicker(
      await findDownloadedCandidates(
        companyName: name,
        domain: dom,
        engine: engine,
      ),
    );
    if (candidates.isEmpty) {
      return LogoFindResult.fail(
        name.isEmpty
            ? 'No logo found for that domain. Try another domain or upload manually.'
            : 'No usable logo found for “$name”. Searched Google, Bing, Clearbit, Brands of the World, and other sources — try a website domain or upload manually.',
      );
    }

    final best = candidates.first;
    return LogoFindResult.ok(
      best.bytes,
      source: best.source,
      hint: best.hint,
    );
  }

  List<LogoCandidate> _clearbitUrlCandidates(
    List<String> domains,
    _RelevanceContext ctx,
  ) {
    return [
      for (final d in domains.take(5))
        LogoCandidate(
          url: 'https://logo.clearbit.com/$d',
          source: 'Clearbit ($d)',
          score: _scoreDomainApi(d, 'Clearbit', ctx),
        ),
    ];
  }

  Future<List<LogoCandidate>> _retoolClearbitCandidates(
    List<String> domains,
    _RelevanceContext ctx,
  ) async {
    final template = _retoolClearbitUrlTemplate();
    if (template.isEmpty) return const [];

    final out = <LogoCandidate>[];
    for (final d in domains.take(4)) {
      final url = template.contains('{domain}')
          ? template.replaceAll('{domain}', d)
          : '$template${template.contains('?') ? '&' : '?'}domain=${Uri.encodeQueryComponent(d)}';
      out.add(
        LogoCandidate(
          url: url,
          source: 'Clearbit via Retool ($d)',
          score: _scoreDomainApi(d, 'Clearbit via Retool', ctx) + 2,
        ),
      );
    }
    return out;
  }

  static String _retoolClearbitUrlTemplate() {
    final env = _optionalEnv('RETOOL_CLEARBIT_LOGO_URL');
    if (env.isNotEmpty) return env;
    return AppConfig.retoolClearbitLogoUrl;
  }

  List<LogoCandidate> _logoDevCandidates(
    List<String> domains,
    _RelevanceContext ctx,
  ) {
    final token = _optionalEnv('LOGO_DEV_TOKEN');
    if (token.isEmpty) return const [];
    return [
      for (final d in domains.take(4))
        LogoCandidate(
          url: 'https://img.logo.dev/$d?token=$token&size=512&format=png',
          source: 'Logo.dev ($d)',
          score: _scoreDomainApi(d, 'Logo.dev', ctx),
        ),
    ];
  }

  List<LogoCandidate> _brandfetchCandidates(
    List<String> domains,
    _RelevanceContext ctx,
  ) {
    final clientId = _optionalEnv('BRANDFETCH_CLIENT_ID');
    if (clientId.isEmpty) return const [];
    return [
      for (final d in domains.take(4))
        LogoCandidate(
          url: 'https://cdn.brandfetch.io/$d/w/512/h/512/logo?c=$clientId',
          source: 'Brandfetch ($d)',
          score: _scoreDomainApi(d, 'Brandfetch', ctx),
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

  Future<List<LogoCandidate>> _bingImageSearch(
    String query,
    _RelevanceContext ctx,
  ) async {
    try {
      final quoted =
          ctx.companyName.isNotEmpty ? '"${ctx.companyName}" logo' : query;
      final encoded = Uri.encodeQueryComponent(quoted);
      final referer = 'https://www.bing.com/images/search?q=$encoded';
      final headers = {..._browserHeaders, 'Referer': referer};

      final urls = <String>{};

      final asyncUri = Uri.parse(
        'https://www.bing.com/images/async?q=$encoded&first=0&count=30&relp=30',
      );
      final asyncRes = await _client
          .get(asyncUri, headers: headers)
          .timeout(const Duration(seconds: 14));
      if (asyncRes.statusCode == 200) {
        urls.addAll(_parseBingMurls(asyncRes.body));
      }

      if (urls.length < 4) {
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

      return _urlCandidatesFromSet(
        urls,
        source: 'Bing Images',
        ctx: ctx,
        sourceBonus: -6,
        minScore: 34,
      );
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

  Future<List<LogoCandidate>> _googleImageSearch(
    String query,
    _RelevanceContext ctx,
  ) async {
    try {
      final urls = <String>{};
      final queries = _googleSearchQueries(ctx, query);

      await Future.wait(
        queries.map((q) => _fetchGoogleImageUrls(q, urls, basicHtml: false)),
      );

      if (urls.length < 4) {
        for (final q in queries.take(3)) {
          await _fetchGoogleImageUrls(q, urls, basicHtml: true);
        }
      }

      if (urls.isEmpty && ctx.domains.isNotEmpty) {
        for (final d in ctx.domains.take(2)) {
          urls.add('https://www.google.com/s2/favicons?domain=$d&sz=256');
          urls.add('https://logo.clearbit.com/$d');
        }
      }

      return _urlCandidatesFromSet(
        urls,
        source: 'Google Images',
        ctx: ctx,
        sourceBonus: 16,
        minScore: 26,
      );
    } catch (_) {
      return const [];
    }
  }

  static List<String> _googleSearchQueries(
    _RelevanceContext ctx,
    String fallbackQuery,
  ) {
    final name = ctx.companyName.trim();
    if (name.isEmpty) return [fallbackQuery];

    final out = <String>{
      '"$name" logo',
      '"$name" logo png',
      '$name logo png',
      '$name logo',
      '$name brand logo',
    };
    for (final d in ctx.domains.take(3)) {
      out.add('site:$d logo');
      out.add('$name logo site:$d');
      out.add('"$name" logo site:$d');
    }
    return out.toList();
  }

  Future<void> _fetchGoogleImageUrls(
    String q,
    Set<String> urls, {
    required bool basicHtml,
  }) async {
    try {
      final params = <String, String>{
        'q': q,
        'tbm': 'isch',
        'hl': 'en',
        'gl': 'us',
        'ijn': '0',
      };
      if (basicHtml) params['gbv'] = '1';

      final uri = Uri.https('www.google.com', '/search', params);
      final res = await _client
          .get(uri, headers: _browserHeaders)
          .timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return;

      _extractGoogleImageUrls(res.body, urls);
    } catch (_) {}
  }

  static void _extractGoogleImageUrls(String html, Set<String> urls) {
    for (final pattern in [
      RegExp(r'"ou":"(https?://[^"]+)"'),
      RegExp(r'\\"ou\\":\\"(https?://[^\\"]+)\\"'),
      RegExp(r'\["ou","(https?://[^"]+)"\]'),
      RegExp(r'"ou":\s*"(https?://[^"]+)"'),
      RegExp(r'imgurl=(https?://[^&"]+)'),
      RegExp(r'imgrefurl=(https?://[^&"]+)'),
      RegExp(r',"(https?://[^"]+\.(?:png|jpe?g|webp|gif)(?:\?[^"]*)?)"'),
      RegExp(r'\[\s*"(https?://[^"]+\.(?:png|jpe?g|webp))"'),
    ]) {
      for (final m in pattern.allMatches(html)) {
        final raw = m.group(1);
        if (raw == null) continue;
        final decoded =
            Uri.decodeComponent(raw.replaceAll(r'\\/', '/').replaceAll(r'\\u003d', '='));
        if (decoded.startsWith('http')) urls.add(decoded);
      }
    }

    for (final m
        in RegExp(r'AF_initDataCallback\(\{[^;]+\}\);', dotAll: true)
            .allMatches(html)) {
      final chunk = m.group(0) ?? '';
      _collectOuFields(chunk, urls);
      _collectInitDataUrls(chunk, urls);
    }

    for (final m in RegExp(
      r'(https?://[^"\s<>]+googleusercontent\.com/[^"\s<>]+)',
    ).allMatches(html)) {
      final u = m.group(1)!;
      if (_isGoogleThumbnail(u)) continue;
      urls.add(u.replaceAll(r'\\u003d', '='));
    }
  }

  static void _collectInitDataUrls(String chunk, Set<String> urls) {
    for (final m in RegExp(
      r'"(https?://[^"]+\.(?:png|jpe?g|webp|gif)(?:\?[^"]*)?)"',
    ).allMatches(chunk)) {
      final u = m.group(1);
      if (u != null && !_isGoogleThumbnail(u)) urls.add(u);
    }
    for (final m in RegExp(r'\[\s*"(https?://[^"]{12,})"').allMatches(chunk)) {
      final u = m.group(1);
      if (u == null || _isGoogleThumbnail(u)) continue;
      if (_looksLikeDirectImageUrl(u)) urls.add(u);
    }
  }

  static bool _isGoogleThumbnail(String url) {
    final lower = url.toLowerCase();
    return lower.contains('=s16') ||
        lower.contains('=s32') ||
        lower.contains('=w16') ||
        lower.contains('=h16') ||
        lower.contains('encrypted-tbn0.gstatic.com') ||
        lower.contains('/imgres?');
  }

  static bool _looksLikeDirectImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.png') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.webp') ||
        lower.contains('.gif') ||
        lower.contains('logo') ||
        lower.contains('brand');
  }

  static void _collectOuFields(String chunk, Set<String> urls) {
    for (final m in RegExp(r'"ou":"(https?://[^"]+)"').allMatches(chunk)) {
      final u = m.group(1);
      if (u != null) urls.add(u);
    }
  }

  Future<List<LogoCandidate>> _brandsOfTheWorldSearch(
    String name,
    _RelevanceContext ctx,
  ) async {
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

      for (final m in RegExp(
        r'https://d1yjjnpx0p53s8\.cloudfront\.net/styles/[^"''>\s]+',
      ).allMatches(html)) {
        final url = m.group(0)!;
        if (url.contains('logo-botw') || url.contains('aotw-envelope')) {
          continue;
        }
        urls.add(url);
      }

      final slugs = <String>{};
      for (final m in RegExp(r'href="(/logo/[^"?]+)"').allMatches(html)) {
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

      return _urlCandidatesFromSet(
        urls,
        source: 'Brands of the World',
        ctx: ctx,
        sourceBonus: 10,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<List<LogoCandidate>> _tineyeSearch(
    String query,
    _RelevanceContext ctx,
  ) async {
    try {
      final q = ctx.companyName.isNotEmpty
          ? '"${ctx.companyName}" logo'
          : query;
      final uri = Uri.https('tineye.com', '/search', {'query': q});
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

      return _urlCandidatesFromSet(
        urls,
        source: 'TinEye',
        ctx: ctx,
        sourceBonus: 0,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<List<LogoCandidate>> _wikipediaCandidates(
    String name,
    _RelevanceContext ctx,
  ) async {
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
      if (searchRes.statusCode != 200) return const [];

      final body = jsonDecode(searchRes.body);
      final hits = body['query']?['search'];
      if (hits is! List || hits.isEmpty) return const [];

      final out = <LogoCandidate>[];
      for (final hit in hits.take(3)) {
        final title = '${hit['title'] ?? ''}';
        if (title.isEmpty) continue;
        final titleScore = _textRelevance(title, ctx);
        if (titleScore < 8) continue;

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
          if (src.isEmpty || !_isAcceptableLogoUrl(src)) continue;
          out.add(
            LogoCandidate(
              url: src,
              source: 'Wikipedia ($title)',
              score: 36 + titleScore + _scoreUrl(src, 'Wikipedia', ctx),
            ),
          );
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<LogoCandidate>> _duckDuckGoCandidates(
    String query,
    _RelevanceContext ctx,
  ) async {
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
      if (res.statusCode != 200) return const [];

      final body = jsonDecode(res.body);
      final out = <LogoCandidate>[];
      final image = '${body['Image'] ?? ''}';
      if (image.isNotEmpty) {
        final imgUrl =
            image.startsWith('http') ? image : 'https://duckduckgo.com$image';
        if (_isAcceptableLogoUrl(imgUrl)) {
          out.add(
            LogoCandidate(
              url: imgUrl,
              source: 'DuckDuckGo',
              score: 30 + _scoreUrl(imgUrl, 'DuckDuckGo', ctx),
            ),
          );
        }
      }

      final related = body['RelatedTopics'];
      if (related is List) {
        for (final item in related.take(8)) {
          if (item is! Map) continue;
          final text = '${item['Text'] ?? ''}';
          final icon = item['Icon'];
          final url = icon is Map ? '${icon['URL'] ?? ''}' : '';
          if (!url.startsWith('http') || !_isAcceptableLogoUrl(url)) continue;
          out.add(
            LogoCandidate(
              url: url,
              source: 'DuckDuckGo',
              score: 24 +
                  _textRelevance(text, ctx) +
                  _scoreUrl(url, 'DuckDuckGo', ctx),
            ),
          );
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<LogoCandidate> _urlCandidatesFromSet(
    Iterable<String> urls, {
    required String source,
    required _RelevanceContext ctx,
    required int sourceBonus,
    int minScore = _minUrlCandidateScore,
  }) {
    final out = <LogoCandidate>[];
    for (final url in urls) {
      if (!_isAcceptableLogoUrl(url)) continue;
      final score = _scoreUrl(url, source, ctx) + sourceBonus;
      if (score < minScore) continue;
      out.add(LogoCandidate(url: url, source: source, score: score));
    }
    return out;
  }

  static List<LogoCandidate> _rankAndDedupe(
    List<LogoCandidate> input,
    _RelevanceContext ctx,
  ) {
    final seen = <String>{};
    final out = <LogoCandidate>[];
    for (final c in input) {
      final key = _urlKey(c.url);
      if (key.isEmpty || !seen.add(key)) continue;
      if (c.score < _minUrlCandidateScore) continue;
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

  static int _scoreDomainApi(
    String domain,
    String source,
    _RelevanceContext ctx,
  ) {
    var score = 72;
    score += _domainMatchBonus(domain, ctx);
    switch (source) {
      case 'Clearbit':
        score += 8;
      case 'Clearbit via Retool':
        score += 9;
      case 'Logo.dev':
        score += 6;
      case 'Brandfetch':
        score += 5;
    }
    return score;
  }

  static int _domainMatchBonus(String domain, _RelevanceContext ctx) {
    var bonus = 0;
    final stem = domain.split('.').first.toLowerCase();
    for (final token in ctx.tokens) {
      if (token.length < 3) continue;
      if (stem.contains(token) || token.contains(stem)) bonus += 18;
    }
    if (ctx.domains.isNotEmpty && ctx.domains.first == domain) bonus += 12;
    return bonus;
  }

  static int _scoreUrl(
    String url,
    String source,
    _RelevanceContext ctx,
  ) {
    var score = 0;
    final lower = url.toLowerCase();
    final host = _hostOf(url);
    final pathAndQuery = lower.replaceFirst(host, '');

    score += _textRelevance('$host $pathAndQuery', ctx);

    if (lower.contains('.png')) score += 12;
    if (lower.contains('.webp')) score += 8;
    if (lower.contains('.jpg') || lower.contains('.jpeg')) score += 5;
    if (lower.contains('.gif')) score += 1;
    if (lower.contains('logo')) score += 10;
    if (lower.contains('brand')) score += 4;
    if (lower.contains('vector') || lower.contains('svg')) score += 3;

    for (final d in ctx.domains) {
      if (host == d || host.endsWith('.$d') || host.contains(d)) {
        score += 28;
        break;
      }
      final stem = d.split('.').first;
      if (stem.length >= 4 && host.contains(stem)) score += 16;
    }

    if (lower.contains('thumb') ||
        lower.contains('thumbnail') ||
        lower.contains('icon') ||
        lower.contains('favicon') ||
        lower.contains('sprite') ||
        lower.contains('avatar') ||
        lower.contains('profile')) {
      score -= 22;
    }
    if (lower.contains('gstatic.com') ||
        lower.contains('googleusercontent.com/imgres') ||
        lower.contains('bing.com/th') ||
        lower.contains('=s16') ||
        lower.contains('=s32') ||
        lower.contains('w=16') ||
        lower.contains('h=16')) {
      score -= 18;
    }

    score -= _junkPenalty(host, lower);

    if (lower.contains('cloudfront.net') &&
        (lower.contains('logo') || source == 'Brands of the World')) {
      score += 8;
    }

    switch (source) {
      case 'Brands of the World':
        score += 6;
      case 'Logo.dev':
      case 'Brandfetch':
      case 'Clearbit':
      case 'Clearbit via Retool':
        break;
      case 'Bing Images':
        if (score < 38) score -= 18;
        else if (score < 42) score -= 8;
      case 'Google Images':
        score += 6;
        if (score < 32) score -= 4;
      case 'TinEye':
        if (score < 32) score -= 6;
      case 'Wikipedia':
        score += 4;
      case 'DuckDuckGo':
        score += 2;
    }
    return score;
  }

  static int _textRelevance(String text, _RelevanceContext ctx) {
    if (ctx.tokens.isEmpty) return 0;
    final normalized = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized.isEmpty) return 0;

    var matched = 0;
    var score = 0;
    for (final token in ctx.tokens) {
      if (token.length < 3) continue;
      if (normalized.contains(token)) {
        matched++;
        score += token.length >= 6 ? 16 : 12;
      }
    }
    if (matched >= 2) score += 10;
    if (matched == 0 && ctx.companyName.isNotEmpty) score -= 18;
    return score;
  }

  static int _junkPenalty(String host, String lower) {
    var penalty = 0;
    const junkHosts = [
      'shutterstock',
      'gettyimages',
      'istockphoto',
      'alamy',
      'dreamstime',
      'depositphotos',
      '123rf',
      'stock.adobe',
      'adobestock',
      'freepik',
      'pngtree',
      'pngwing',
      'cleanpng',
      'pinimg',
      'pinterest',
      'facebook',
      'twitter',
      'instagram',
      'tiktok',
      'reddit',
      'youtube',
      'linkedin',
      'cnn.com',
      'bbc.',
      'forbes',
      'people.com',
      'celebrity',
      'news.',
      'blog.',
      'wordpress.com',
      'medium.com',
      'ebay.',
      'amazon.',
      'walmart.',
    ];
    for (final junk in junkHosts) {
      if (host.contains(junk) || lower.contains(junk)) {
        penalty += 35;
        break;
      }
    }

    const junkPaths = [
      'stock-photo',
      'stockphoto',
      'headshot',
      'portrait',
      'news/',
      '/article/',
      '/articles/',
      'press-release',
      'thumbnail',
    ];
    for (final junk in junkPaths) {
      if (lower.contains(junk)) {
        penalty += 20;
        break;
      }
    }
    return penalty;
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  static List<String> _companyTokens(String companyName) {
    final cleaned = companyName
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'\b(inc|incorporated|ltd|limited|llc|corp|corporation|co|company|plc|lp|partnership|the|and|of|for)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return const [];

    final tokens = <String>{};
    for (final word in cleaned.split(' ')) {
      if (word.length >= 3) tokens.add(word);
    }
    tokens.add(cleaned.replaceAll(' ', ''));
    if (cleaned.contains(' ')) {
      tokens.add(cleaned.replaceAll(' ', '-'));
    }
    return tokens.toList();
  }

  static int _bytesBonus(Uint8List bytes) {
    final len = bytes.length;
    if (len >= 8000 && len <= 900_000) return 6;
    if (len < 2500) return -8;
    return 0;
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
        lower.contains('cloudfront.net') ||
        lower.contains('logo.clearbit.com') ||
        lower.contains('img.logo.dev') ||
        lower.contains('cdn.brandfetch.io') ||
        lower.contains('google.com/s2/favicons');
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

  static List<String> _uniqueDomains(String name, String dom) {
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
    const tlds = [
      '.com',
      '.ca',
      '.com.au',
      '.co.uk',
      '.net',
      '.org',
      '.co',
      '.io',
    ];
    final out = <String>{};
    for (final tld in tlds) {
      out.add('$compact$tld');
      if (dashed != compact) out.add('$dashed$tld');
    }
    final words = cleaned.split(' ');
    if (words.length >= 2) {
      out.add('${words.first}${words[1]}.com');
      out.add('${words.first}.com');
      out.add('${words.first}${words[1]}.ca');
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
