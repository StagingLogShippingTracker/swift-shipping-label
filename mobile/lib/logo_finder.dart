import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'gemini_client.dart';

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
    this.extraQueries = const [],
    this.alternateNames = const [],
  });

  final String companyName;
  final List<String> domains;
  final List<String> tokens;
  /// Gemini (or other) extra image-search queries.
  final List<String> extraQueries;
  /// Alternate company names suggested by Gemini.
  final List<String> alternateNames;

  factory _RelevanceContext.from(
    String companyName,
    List<String> domains, {
    List<String> extraQueries = const [],
    List<String> alternateNames = const [],
  }) {
    return _RelevanceContext(
      companyName: companyName.trim(),
      domains: domains,
      tokens: LogoFinder._companyTokens(companyName),
      extraQueries: extraQueries,
      alternateNames: alternateNames,
    );
  }

  _RelevanceContext withExtras({
    List<String>? extraQueries,
    List<String>? alternateNames,
    List<String>? domains,
  }) {
    return _RelevanceContext(
      companyName: companyName,
      domains: domains ?? this.domains,
      tokens: tokens,
      extraQueries: extraQueries ?? this.extraQueries,
      alternateNames: alternateNames ?? this.alternateNames,
    );
  }
}

/// Multi-source logo lookup: Clearbit, image search (Google, Bing), logo libraries
/// (Brands of the World, Logo.dev, Brandfetch), Wikipedia / DuckDuckGo fallbacks.
class LogoFinder {
  LogoFinder({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const maxBytes = 5 * 1024 * 1024;
  /// Max thumbnails shown in the post-search logo picker grid.
  static const pickerMaxResults = 20;
  static const _maxCandidatesToDownload = 40;
  static const _minUrlCandidateScore = 24;
  static const _minDownloadedScore = 26;
  static const _pickerMinScore = 24;
  /// Per-request timeout so one blocked engine cannot stall All Sources.
  static const _requestTimeout = Duration(seconds: 6);
  /// Whole-engine budget (multiple queries / fallbacks inside one source).
  static const _engineTimeout = Duration(seconds: 18);
  static const _ua =
      'SwiftShippingLabel/1.0 (+https://github.com/StagingLogShippingTracker/swift-shipping-label)';

  /// Rotating desktop Chrome profiles (User-Agent + matching Sec-Ch-Ua).
  static const _chromeProfiles = <({String ua, String secChUa, String version})>[
    (
      version: '131',
      ua:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      secChUa:
          '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
    ),
    (
      version: '132',
      ua:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36',
      secChUa:
          '"Not A(Brand";v="8", "Chromium";v="132", "Google Chrome";v="132"',
    ),
    (
      version: '133',
      ua:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
      secChUa:
          '"Not(A:Brand";v="99", "Google Chrome";v="133", "Chromium";v="133"',
    ),
    (
      version: '134',
      ua:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
      secChUa:
          '"Chromium";v="134", "Google Chrome";v="134", "Not:A-Brand";v="24"',
    ),
    (
      version: '135',
      ua:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
      secChUa:
          '"Google Chrome";v="135", "Not-A.Brand";v="8", "Chromium";v="135"',
    ),
  ];

  static int _uaRotate = 0;

  static ({String ua, String secChUa, String version}) _nextChromeProfile() {
    final profile = _chromeProfiles[_uaRotate % _chromeProfiles.length];
    _uaRotate++;
    return profile;
  }

  /// Desktop Chrome-like headers for HTML scrapers (Google / Bing / DDG / BOTW).
  static Map<String, String> _browserHeadersRotating({String? referer}) {
    final p = _nextChromeProfile();
    final headers = <String, String>{
      'User-Agent': p.ua,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Sec-Ch-Ua': p.secChUa,
      'Sec-Ch-Ua-Mobile': '?0',
      'Sec-Ch-Ua-Platform': p.ua.contains('Macintosh') ? '"macOS"' : '"Windows"',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': referer == null ? 'none' : 'same-origin',
      'Sec-Fetch-User': '?1',
      'Upgrade-Insecure-Requests': '1',
    };
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    }
    return headers;
  }

  static Map<String, String> _browserHeadersFor(Uri uri) =>
      _browserHeadersRotating(referer: '${uri.scheme}://${uri.host}/');

  static Map<String, String> _imageDownloadHeaders(Uri uri) {
    final p = _nextChromeProfile();
    return {
      'User-Agent': p.ua,
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Sec-Ch-Ua': p.secChUa,
      'Sec-Ch-Ua-Mobile': '?0',
      'Sec-Ch-Ua-Platform': p.ua.contains('Macintosh') ? '"macOS"' : '"Windows"',
      'Sec-Fetch-Dest': 'image',
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'cross-site',
      'Referer': '${uri.scheme}://${uri.host}/',
    };
  }


  /// Ranked list for the picker UI — top [pickerMaxResults] by score, with light
  /// junk filtering. Callers must always show the grid when this is non-empty.
  static List<LogoDownloadedCandidate> filterForPicker(
    List<LogoDownloadedCandidate> candidates,
  ) {
    if (candidates.isEmpty) return candidates;
    final sorted = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
    final usable = sorted.where((c) => c.score >= _pickerMinScore).toList();
    final pool = usable.isNotEmpty ? usable : sorted;
    return pool.take(pickerMaxResults).toList();
  }

  /// Test hooks for HTML/JSON crawler parsers (no network).
  static Set<String> debugParseBingPayload(String body) =>
      _parseBingImagePayload(body).toSet();

  static Set<String> debugParseGoogleHtml(String html) {
    final urls = <String>{};
    _extractGoogleImageUrls(html, urls);
    return urls;
  }

  static List<String> debugPrimaryQueries(String companyName, {String domain = ''}) {
    final domains = domain.trim().isEmpty ? <String>[] : [domain.trim()];
    return _primaryLogoQueries(_RelevanceContext.from(companyName, domains));
  }

  static List<String> debugExpandedQueries(String companyName, {String domain = ''}) {
    final domains = domain.trim().isEmpty ? <String>[] : [domain.trim()];
    return _expandedLogoQueries(_RelevanceContext.from(companyName, domains));
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

    var domainList = await _resolveDomains(name, dom);

    // Gemini search plan — queries / domains / URL hints (fail-open, parallel-safe).
    final gemini = GeminiClient.isConfigured ? GeminiClient(client: _client) : null;
    GeminiLogoSearchPlan? plan;
    if (gemini != null && name.isNotEmpty) {
      try {
        plan = await gemini
            .suggestLogoSearchPlan(
              companyName: name,
              knownDomains: domainList,
            )
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        plan = null;
      }
    }

    if (plan != null) {
      domainList = _mergeGeminiDomains(domainList, plan.officialDomains, name);
    }

    final extraQueries = <String>[
      if (plan != null) ...plan.searchQueries,
      if (plan != null)
        for (final alt in plan.alternateNames.take(4)) ...[
          '$alt logo png',
          '$alt logo',
          '$alt brand vector logo',
        ],
    ];

    final ctx = _RelevanceContext.from(
      name,
      domainList,
      extraQueries: extraQueries,
      alternateNames: plan?.alternateNames ?? const [],
    );
    final useAll = engine == LogoSearchEngine.all;
    bool use(LogoSearchEngine e) => useAll || engine == e;

    // Each source is independently trapped — one failure must not zero out All Sources.
    final futures = <Future<List<LogoCandidate>>>[];
    if (use(LogoSearchEngine.clearbit)) {
      futures.add(
        _safeSource(() async => _clearbitUrlCandidates(domainList, ctx)),
      );
    }
    if (use(LogoSearchEngine.retoolClearbit)) {
      futures.add(
        _safeSource(() => _retoolClearbitCandidates(domainList, ctx)),
      );
    }
    if (use(LogoSearchEngine.logoDev)) {
      futures.add(
        _safeSource(() async => _logoDevCandidates(domainList, ctx)),
      );
    }
    if (use(LogoSearchEngine.brandfetch)) {
      futures.add(
        _safeSource(() async => _brandfetchCandidates(domainList, ctx)),
      );
    }
    if (use(LogoSearchEngine.bing)) {
      futures.add(_safeSource(() => _bingImageSearch(ctx)));
    }
    if (use(LogoSearchEngine.google)) {
      futures.add(_safeSource(() => _googleImageSearch(ctx)));
    }
    if (use(LogoSearchEngine.brandsOfTheWorld) && name.isNotEmpty) {
      futures.add(
        _safeSource(() => _brandsOfTheWorldSearch(name, ctx)),
      );
    }
    if (use(LogoSearchEngine.tineye)) {
      futures.add(_safeSource(() => _tineyeSearch(ctx)));
    }
    if (use(LogoSearchEngine.wikipediaDuckDuckGo) && name.isNotEmpty) {
      futures.add(_safeSource(() => _wikipediaCandidates(name, ctx)));
      futures.add(
        _safeSource(() => _duckDuckGoCandidates(ctx)),
      );
      futures.add(
        _safeSource(() => _duckDuckGoImageSearch(ctx)),
      );
    }

    // Gemini-suggested direct logo URLs (only when the model is highly confident).
    if (plan != null && plan.logoUrlHints.isNotEmpty) {
      futures.add(
        _safeSource(() async => _geminiUrlHintCandidates(plan!, ctx)),
      );
    }

    // Fail-safe aggregation: never let a single rejected future cancel the rest.
    final urlLists = await Future.wait(
      futures.map(
        (f) => f.catchError((Object _, StackTrace __) => <LogoCandidate>[]),
      ),
    );

    final merged = <LogoCandidate>[];
    for (final list in urlLists) {
      merged.addAll(list);
    }

    // Always include Google Favicon as a last-resort URL candidate when we have domains.
    if (useAll || use(LogoSearchEngine.google) || use(LogoSearchEngine.clearbit)) {
      for (final d in domainList.take(3)) {
        merged.add(
          LogoCandidate(
            url: 'https://www.google.com/s2/favicons?sz=256&domain_url=$d',
            source: 'Google Favicon ($d)',
            score: 28 + _domainMatchBonus(d, ctx),
          ),
        );
      }
    }

    var ranked = _rankAndDedupe(merged, ctx);

    // Download candidates in parallel batches so "All sources" merges as
    // well as any single engine (top ~20 by score after byte bonus).
    var toTry = ranked.take(_maxCandidatesToDownload).toList();
    var downloaded = await _downloadCandidatesParallel(toTry, ctx, gemini: gemini);

    // Sparse rescue: if scrapers under-delivered, re-run Google/Bing with Gemini queries only.
    if (downloaded.length < 3 &&
        gemini != null &&
        plan != null &&
        (use(LogoSearchEngine.google) || use(LogoSearchEngine.bing))) {
      try {
        final rescueCtx = ctx.withExtras(
          extraQueries: [
            ...plan.searchQueries,
            for (final alt in plan.alternateNames.take(3)) '$alt official logo png',
          ],
        );
        final rescueFutures = <Future<List<LogoCandidate>>>[];
        if (use(LogoSearchEngine.google)) {
          rescueFutures.add(_safeSource(() => _googleImageSearch(rescueCtx, forceExpanded: true)));
        }
        if (use(LogoSearchEngine.bing)) {
          rescueFutures.add(_safeSource(() => _bingImageSearch(rescueCtx, forceExpanded: true)));
        }
        final rescueLists = await Future.wait(
          rescueFutures.map(
            (f) => f.catchError((Object _, StackTrace __) => <LogoCandidate>[]),
          ),
        );
        final rescueMerged = <LogoCandidate>[...merged];
        for (final list in rescueLists) {
          rescueMerged.addAll(list);
        }
        ranked = _rankAndDedupe(rescueMerged, rescueCtx);
        toTry = ranked.take(_maxCandidatesToDownload).toList();
        final more = await _downloadCandidatesParallel(toTry, rescueCtx, gemini: gemini);
        final seen = {for (final c in downloaded) _urlKey(c.url)};
        for (final c in more) {
          final key = _urlKey(c.url);
          if (key.isEmpty || seen.add(key)) downloaded.add(c);
        }
      } catch (_) {
        // Fail open — keep first-pass downloads.
      }
    }

    if (downloaded.isNotEmpty) {
      downloaded = await _maybeGeminiRerank(downloaded, gemini, name);
      downloaded.sort((a, b) => b.score.compareTo(a.score));
      return filterForPicker(downloaded);
    }

    // Favicon byte download fallback (may be tiny — keep as last ditch).
    for (final d in domainList.take(3)) {
      final fav = await _downloadImage(
        Uri.parse('https://www.google.com/s2/favicons?sz=256&domain_url=$d'),
        source: 'Favicon ($d)',
        minBytes: 400,
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

  static List<String> _mergeGeminiDomains(
    List<String> existing,
    List<String> suggested,
    String companyName,
  ) {
    final out = [...existing];
    final seen = out.toSet();
    for (final raw in suggested) {
      final d = _normalizeDomain(raw);
      if (d.isEmpty || !seen.add(d)) continue;
      if (!_domainLooksCorporate(d, companyName)) continue;
      // Prefer Gemini domains near the front (after an explicit user domain).
      final insertAt = existing.isNotEmpty && out.isNotEmpty ? 1 : 0;
      out.insert(insertAt > out.length ? out.length : insertAt, d);
    }
    // Deduplicate while preserving order.
    final dedup = <String>{};
    return [for (final d in out) if (dedup.add(d)) d];
  }

  List<LogoCandidate> _geminiUrlHintCandidates(
    GeminiLogoSearchPlan plan,
    _RelevanceContext ctx,
  ) {
    final out = <LogoCandidate>[];
    for (final url in plan.logoUrlHints.take(6)) {
      if (!_isAcceptableLogoUrl(url)) continue;
      out.add(
        LogoCandidate(
          url: url,
          source: 'Gemini URL hint',
          score: 70 + _scoreUrl(url, 'Gemini URL hint', ctx),
        ),
      );
    }
    return out;
  }

  Future<List<LogoDownloadedCandidate>> _maybeGeminiRerank(
    List<LogoDownloadedCandidate> downloaded,
    GeminiClient? gemini,
    String companyName,
  ) async {
    if (gemini == null || downloaded.length < 3) return downloaded;
    try {
      final top = downloaded.take(6).toList();
      final order = await gemini
          .rankLogoCandidates(
            [for (final c in top) c.bytes],
            companyHint: companyName,
          )
          .timeout(const Duration(seconds: 20));
      if (order == null || order.isEmpty) return downloaded;

      final rerankedTop = <LogoDownloadedCandidate>[];
      for (var i = 0; i < order.length; i++) {
        final idx = order[i];
        if (idx < 0 || idx >= top.length) continue;
        final c = top[idx];
        // Boost earlier ranks so picker sort favors Gemini's preference.
        rerankedTop.add(
          LogoDownloadedCandidate(
            bytes: c.bytes,
            source: c.source.contains('Gemini') ? c.source : '${c.source} · Gemini rank',
            url: c.url,
            score: c.score + (18 - i * 3).clamp(0, 18),
            hint: c.hint,
          ),
        );
      }
      final rest = downloaded.skip(top.length);
      return [...rerankedTop, ...rest];
    } catch (_) {
      return downloaded;
    }
  }

  /// Isolate one engine/source so errors never propagate to All Sources.
  Future<List<LogoCandidate>> _safeSource(
    Future<List<LogoCandidate>> Function() run,
  ) async {
    try {
      return await run().timeout(
        _engineTimeout,
        onTimeout: () => <LogoCandidate>[],
      );
    } catch (_) {
      return const [];
    }
  }

  Future<List<LogoDownloadedCandidate>> _downloadCandidatesParallel(
    List<LogoCandidate> candidates,
    _RelevanceContext ctx, {
    GeminiClient? gemini,
  }) async {
    if (candidates.isEmpty) return const [];

    const batchSize = 8;
    final out = <LogoDownloadedCandidate>[];
    final vision = gemini ??
        (GeminiClient.isConfigured ? GeminiClient(client: _client) : null);

    for (var start = 0; start < candidates.length; start += batchSize) {
      if (out.length >= pickerMaxResults) break;
      final batch = candidates.skip(start).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((c) async {
          try {
            final uri = Uri.tryParse(c.url);
            if (uri == null || !uri.hasScheme) return null;
            final isFavicon = c.source.toLowerCase().contains('favicon');
            final dl = await _downloadImage(
              uri,
              source: c.source,
              minBytes: isFavicon ? 400 : 1200,
            );
            if (!dl.ok) return null;

            // Gemini vision gate — discard photos / junk scraped as "logos".
            // Fail-open when Gemini is unavailable so warehouse workflows continue.
            if (vision != null && !isFavicon) {
              try {
                final verdict = await vision.validateLogoCandidate(
                  dl.bytes!,
                  companyHint: ctx.companyName,
                );
                if (verdict != null && !verdict.shouldKeep) {
                  return null;
                }
                if (verdict != null && verdict.confidenceScore >= 0.7) {
                  // Small bonus for high-confidence validated logos.
                  final finalScore =
                      c.score + _bytesBonus(dl.bytes!) + 6;
                  if (finalScore < _minDownloadedScore) return null;
                  return LogoDownloadedCandidate(
                    bytes: dl.bytes!,
                    source: '${c.source} · Gemini',
                    url: c.url,
                    score: finalScore,
                  );
                }
              } catch (_) {
                // Fail open.
              }
            }

            final finalScore = c.score + _bytesBonus(dl.bytes!);
            if (!isFavicon && finalScore < _minDownloadedScore) return null;
            return LogoDownloadedCandidate(
              bytes: dl.bytes!,
              source: c.source,
              url: c.url,
              score: finalScore,
              hint: isFavicon
                  ? 'Low-resolution favicon — upload a better logo if needed.'
                  : '',
            );
          } catch (_) {
            return null;
          }
        }).map(
          (f) => f.catchError((Object _, StackTrace __) => null),
        ),
      );
      for (final item in results) {
        if (item != null) out.add(item);
      }
    }
    return out;
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

    return const LogoFindResult.fail(
      'Logo candidates found — show the picker and let the user choose.',
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
    _RelevanceContext ctx, {
    bool forceExpanded = false,
  }) async {
    try {
      final urls = <String>{};
      // Primary query first; expand only when empty / sparse (or Gemini rescue).
      final primary = forceExpanded
          ? _queriesForSearch(ctx, expanded: true)
          : _queriesForSearch(ctx, expanded: false, includePrimary: true);
      final expanded = _queriesForSearch(ctx, expanded: true);

      Future<void> runQueries(List<String> queries) async {
        for (final q in queries) {
          if (urls.length >= 28) break;
          try {
            final encoded = Uri.encodeQueryComponent(q);
            final referer = 'https://www.bing.com/images/search?q=$encoded';
            final headers = _browserHeadersRotating(referer: referer)
              ..['Sec-Fetch-Site'] = 'same-origin';

            final asyncUri = Uri.parse(
              'https://www.bing.com/images/async?q=$encoded&first=0&count=35&relp=35&tsc=ImageBasicHover&qft=+filterui:photo-photo',
            );
            final asyncRes = await _client
                .get(asyncUri, headers: headers)
                .timeout(_requestTimeout);
            if (asyncRes.statusCode == 200) {
              urls.addAll(_parseBingImagePayload(asyncRes.body));
            }

            if (urls.length < 8) {
              final pageUri = Uri.parse(
                'https://www.bing.com/images/search?q=$encoded&form=HDRSC2&first=1&tsc=ImageBasicHover',
              );
              final pageRes = await _client
                  .get(pageUri, headers: headers)
                  .timeout(_requestTimeout);
              if (pageRes.statusCode == 200) {
                urls.addAll(_parseBingImagePayload(pageRes.body));
              }
            }
          } catch (_) {
            continue;
          }
        }
      }

      await runQueries(primary);
      if (urls.isEmpty) {
        await runQueries(expanded);
      } else if (urls.length < 6) {
        await runQueries(expanded.take(4).toList());
      }

      return _urlCandidatesFromSet(
        urls,
        source: 'Bing Images',
        ctx: ctx,
        sourceBonus: -4,
        minScore: 30,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Extract high-res Bing media URLs (`murl` / `mediaurl`) from HTML or JSON.
  static Iterable<String> _parseBingImagePayload(String body) sync* {
    final seen = <String>{};

    // Prefer structured `m="{...}"` / `m='{...}'` containers (Bing iusc cards).
    for (final m in RegExp(
      r'''\bm=["'](\{.*?\})["']''',
      dotAll: true,
    ).allMatches(body)) {
      final raw = m.group(1);
      if (raw == null) continue;
      final jsonStr = _htmlUnescape(raw);
      try {
        final obj = jsonDecode(jsonStr);
        if (obj is Map) {
          for (final key in ['murl', 'mediaurl', 'purl']) {
            final v = obj[key];
            if (v is String && v.startsWith('http')) {
              seen.add(_unescapeJsonUrl(v));
            }
          }
        }
      } catch (_) {
        for (final mm in RegExp(r'"murl"\s*:\s*"(https?://[^"]+)"')
            .allMatches(jsonStr)) {
          final u = mm.group(1);
          if (u != null) seen.add(_unescapeJsonUrl(u));
        }
      }
    }

    // HTML-entity encoded murls common in async HTML.
    for (final pattern in [
      RegExp(r'murl&quot;:&quot;(https?://[^&]+?)&quot;'),
      RegExp(r'mediaurl&quot;:&quot;(https?://[^&]+?)&quot;'),
      RegExp(r'"murl"\s*:\s*"(https?://[^"]+)"'),
      RegExp(r'"mediaurl"\s*:\s*"(https?://[^"]+)"'),
      RegExp(r'"murl"\s*:\s*"(https?:\\/\\/[^"]+)"'),
      RegExp(r'murl\\?":\\?"(https?://[^"\\]+)'),
    ]) {
      for (final m in pattern.allMatches(body)) {
        final url = m.group(1);
        if (url != null) seen.add(_unescapeJsonUrl(url));
      }
    }

    // Compact JSON objects that carry murl.
    for (final m in RegExp(
      r'\{[^{}]{0,40}"murl"\s*:\s*"(https?://[^"]+)"[^{}]{0,400}\}',
    ).allMatches(body)) {
      try {
        final obj = jsonDecode(m.group(0)!);
        if (obj is Map && obj['murl'] is String) {
          seen.add(_unescapeJsonUrl(obj['murl'] as String));
        }
      } catch (_) {
        final u = m.group(1);
        if (u != null) seen.add(_unescapeJsonUrl(u));
      }
    }

    for (final u in seen) {
      if (u.startsWith('http')) yield u;
    }
  }

  Future<List<LogoCandidate>> _googleImageSearch(
    _RelevanceContext ctx, {
    bool forceExpanded = false,
  }) async {
    try {
      final urls = <String>{};
      final primary = forceExpanded
          ? _queriesForSearch(ctx, expanded: true)
          : _queriesForSearch(ctx, expanded: false, includePrimary: true);
      final expanded = _queriesForSearch(ctx, expanded: true);

      Future<void> runQueries(List<String> queries, {required bool basicHtml}) async {
        await Future.wait(
          queries.take(5).map(
                (q) => _fetchGoogleImageUrls(q, urls, basicHtml: basicHtml)
                    .catchError((Object _, StackTrace __) {}),
              ),
        );
      }

      await runQueries(primary, basicHtml: false);
      if (urls.isEmpty) {
        await runQueries(expanded, basicHtml: false);
      }

      if (urls.length < 4) {
        await runQueries(
          urls.isEmpty ? [...primary, ...expanded.take(3)] : primary,
          basicHtml: true,
        );
      }

      // Newer Google Images UI (`udm=2`) as an extra fallback.
      if (urls.length < 4) {
        final fallbackQs = urls.isEmpty ? [...primary, ...expanded.take(3)] : primary;
        for (final q in fallbackQs.take(4)) {
          await _fetchGoogleUdmImageUrls(q, urls);
        }
      }

      // Still empty after primary — force full expansion cycle.
      if (urls.isEmpty) {
        await runQueries(expanded, basicHtml: false);
        await runQueries(expanded, basicHtml: true);
      }

      return _urlCandidatesFromSet(
        urls,
        source: 'Google Images',
        ctx: ctx,
        sourceBonus: 16,
        minScore: 24,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Direct `{Company} logo png` (+ light aliases) tried first.
  static List<String> _primaryLogoQueries(_RelevanceContext ctx) {
    final name = ctx.companyName.trim();
    if (name.isEmpty) {
      if (ctx.domains.isEmpty) return const ['logo png'];
      final d = ctx.domains.first;
      return ['$d logo png', '${d.split('.').first} logo png'];
    }
    return <String>[
      '$name logo png',
      '$name logo',
    ];
  }

  /// Smart synonyms used when the primary `{name} logo png` search is empty.
  static List<String> _expandedLogoQueries(_RelevanceContext ctx) {
    final name = ctx.companyName.trim();
    if (name.isEmpty) {
      if (ctx.domains.isEmpty) return const ['brand vector logo'];
      final d = ctx.domains.first;
      final stem = d.split('.').first;
      return [
        '$stem brand vector logo',
        '$stem corporate logo transparent background',
        '$stem official website logo',
        'site:$d logo',
      ];
    }
    final out = <String>{
      '$name brand vector logo',
      '$name corporate logo transparent background',
      '$name official website logo',
      '$name company logo',
      '$name brand logo',
      '$name official logo',
      '"$name" logo png',
      '"$name" logo',
    };
    for (final d in ctx.domains.take(4)) {
      out.add('site:$d logo');
      out.add('$name logo site:$d');
      out.add('${d.split('.').first} logo');
    }
    return out.toList();
  }

  /// Combined query ladder (primary then expanded + Gemini extras).
  static List<String> _imageSearchQueries(_RelevanceContext ctx) {
    return _queriesForSearch(ctx, expanded: true, includePrimary: true);
  }

  static List<String> _queriesForSearch(
    _RelevanceContext ctx, {
    required bool expanded,
    bool includePrimary = false,
  }) {
    final seen = <String>{};
    final out = <String>[];
    void addAll(Iterable<String> qs) {
      for (final q in qs) {
        final t = q.trim();
        if (t.isEmpty) continue;
        if (seen.add(t)) out.add(t);
      }
    }

    if (includePrimary || !expanded) addAll(_primaryLogoQueries(ctx));
    if (expanded) {
      addAll(_expandedLogoQueries(ctx));
      addAll(ctx.extraQueries);
      for (final alt in ctx.alternateNames.take(4)) {
        addAll([
          '$alt logo png',
          '$alt brand vector logo',
          '$alt corporate logo transparent background',
        ]);
      }
    } else {
      // Primary path still benefits from a few Gemini hints when present.
      addAll(ctx.extraQueries.take(3));
    }
    return out;
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
        'safe': 'off',
        'tbs': 'itp:photo,ift:png',
      };
      if (basicHtml) {
        params['gbv'] = '1';
        params.remove('tbs');
      }

      final uri = Uri.https('www.google.com', '/search', params);
      final res = await _client
          .get(uri, headers: _browserHeadersFor(uri))
          .timeout(_requestTimeout);
      if (res.statusCode != 200) return;

      _extractGoogleImageUrls(res.body, urls);
    } catch (_) {}
  }

  Future<void> _fetchGoogleUdmImageUrls(String q, Set<String> urls) async {
    try {
      final uri = Uri.https('www.google.com', '/search', {
        'q': q,
        'udm': '2',
        'hl': 'en',
        'gl': 'us',
        'safe': 'off',
      });
      final res = await _client
          .get(uri, headers: _browserHeadersFor(uri))
          .timeout(_requestTimeout);
      if (res.statusCode != 200) return;
      _extractGoogleImageUrls(res.body, urls);
    } catch (_) {}
  }

  static void _extractGoogleImageUrls(String html, Set<String> urls) {
    // 1) Classic / still-present JSON keys in image result payloads.
    for (final pattern in [
      RegExp(r'"ou"\s*:\s*"(https?://[^"]+)"'),
      RegExp(r'\\"ou\\"\s*:\s*\\"(https?://[^\\"]+)\\"'),
      RegExp(r'\["ou","(https?://[^"]+)"\]'),
      RegExp(r'"originalUrl"\s*:\s*"(https?://[^"]+)"'),
      RegExp(r'"imageUrl"\s*:\s*"(https?://[^"]+)"'),
      RegExp(r'"ow"\s*:\s*\d+\s*,\s*"oh"\s*:\s*\d+\s*,\s*"ou"\s*:\s*"(https?://[^"]+)"'),
      RegExp(r'imgurl=(https?://[^&"]+)'),
      RegExp(r',"(https?://[^"]+\.(?:png|jpe?g|webp|gif)(?:\?[^"]*)?)"'),
      RegExp(r'\[\s*"(https?://[^"]+\.(?:png|jpe?g|webp))"'),
    ]) {
      for (final m in pattern.allMatches(html)) {
        _offerGoogleUrl(m.group(1), urls);
      }
    }

    // 2) Data attributes used by newer Google Images UI.
    for (final pattern in [
      RegExp(r'data-src="(https?://[^"]+)"'),
      RegExp(r"data-src='(https?://[^']+)'"),
      RegExp(r'data-iurl="(https?://[^"]+)"'),
      RegExp(r'data-ils="[^"]*"[^>]*src="(https?://[^"]+)"'),
      RegExp(r'data-deferred="1"[^>]*src="(https?://[^"]+)"'),
      RegExp(r'data-iml="[^"]*"[^>]*(?:data-src|src)="(https?://[^"]+)"'),
    ]) {
      for (final m in pattern.allMatches(html)) {
        _offerGoogleUrl(m.group(1), urls);
      }
    }

    // 3) AF_initDataCallback script blocks — walk embedded data arrays.
    for (final chunk in _extractAfInitDataChunks(html)) {
      _collectOuFields(chunk, urls);
      _collectInitDataUrls(chunk, urls);
      _walkEmbeddedJsonForImageUrls(chunk, urls);
    }

    // 4) `<script>` blobs that look like image result JSON.
    for (final m in RegExp(
      r'<script[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html)) {
      final script = m.group(1) ?? '';
      if (script.length < 80) continue;
      if (!script.contains('http') ||
          !(script.contains('ou') ||
              script.contains('imageUrl') ||
              script.contains('.png') ||
              script.contains('AF_initDataCallback'))) {
        continue;
      }
      _collectOuFields(script, urls);
      _collectInitDataUrls(script, urls);
    }

    for (final m in RegExp(
      r'(https?://[^"\s<>]+googleusercontent\.com/[^"\s<>]+)',
    ).allMatches(html)) {
      _offerGoogleUrl(m.group(1), urls);
    }
  }

  static void _offerGoogleUrl(String? raw, Set<String> urls) {
    if (raw == null || raw.isEmpty) return;
    final decoded = _unescapeJsonUrl(raw);
    if (!decoded.startsWith('http')) return;
    if (_isGoogleThumbnail(decoded)) return;
    urls.add(decoded);
  }

  /// Pull `AF_initDataCallback({...})` payloads with nested-brace awareness.
  static Iterable<String> _extractAfInitDataChunks(String html) sync* {
    const marker = 'AF_initDataCallback(';
    var from = 0;
    while (true) {
      final start = html.indexOf(marker, from);
      if (start < 0) break;
      final brace = html.indexOf('{', start + marker.length);
      if (brace < 0) break;
      final end = _findMatchingBrace(html, brace);
      if (end < 0) {
        from = start + marker.length;
        continue;
      }
      yield html.substring(brace, end + 1);
      from = end + 1;
    }
  }

  static int _findMatchingBrace(String s, int openIdx) {
    if (openIdx < 0 || openIdx >= s.length || s[openIdx] != '{') return -1;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = openIdx; i < s.length; i++) {
      final ch = s[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == r'\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static void _walkEmbeddedJsonForImageUrls(String chunk, Set<String> urls) {
    // Attempt to decode the AF callback object and walk for URL-looking strings.
    try {
      final decoded = jsonDecode(chunk);
      _walkJsonForUrls(decoded, urls, depth: 0);
      return;
    } catch (_) {}

    // Callbacks often wrap data in `data:` key with a JS array — extract that array.
    final dataIdx = chunk.indexOf('"data"');
    if (dataIdx < 0) return;
    final colon = chunk.indexOf(':', dataIdx);
    if (colon < 0) return;
    var i = colon + 1;
    while (i < chunk.length && (chunk[i] == ' ' || chunk[i] == '\n')) {
      i++;
    }
    if (i >= chunk.length) return;
    if (chunk[i] == '[') {
      final end = _findMatchingBracket(chunk, i);
      if (end > i) {
        try {
          final arr = jsonDecode(chunk.substring(i, end + 1));
          _walkJsonForUrls(arr, urls, depth: 0);
        } catch (_) {}
      }
    } else if (chunk[i] == '{') {
      final end = _findMatchingBrace(chunk, i);
      if (end > i) {
        try {
          final obj = jsonDecode(chunk.substring(i, end + 1));
          _walkJsonForUrls(obj, urls, depth: 0);
        } catch (_) {}
      }
    }
  }

  static int _findMatchingBracket(String s, int openIdx) {
    if (openIdx < 0 || openIdx >= s.length || s[openIdx] != '[') return -1;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = openIdx; i < s.length; i++) {
      final ch = s[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == r'\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static void _walkJsonForUrls(Object? node, Set<String> urls, {required int depth}) {
    if (depth > 14 || node == null) return;
    if (node is String) {
      if (node.startsWith('http') && _looksLikeDirectImageUrl(node)) {
        _offerGoogleUrl(node, urls);
      }
      return;
    }
    if (node is List) {
      for (final item in node) {
        _walkJsonForUrls(item, urls, depth: depth + 1);
      }
      return;
    }
    if (node is Map) {
      for (final entry in node.entries) {
        final key = '${entry.key}'.toLowerCase();
        final value = entry.value;
        if (value is String &&
            value.startsWith('http') &&
            (key.contains('ou') ||
                key.contains('url') ||
                key.contains('image') ||
                key.contains('src'))) {
          _offerGoogleUrl(value, urls);
        }
        _walkJsonForUrls(value, urls, depth: depth + 1);
      }
    }
  }

  static void _collectInitDataUrls(String chunk, Set<String> urls) {
    for (final m in RegExp(
      r'"(https?://[^"]+\.(?:png|jpe?g|webp|gif)(?:\?[^"]*)?)"',
    ).allMatches(chunk)) {
      _offerGoogleUrl(m.group(1), urls);
    }
    for (final m in RegExp(r'\[\s*"(https?://[^"]{12,})"').allMatches(chunk)) {
      final u = m.group(1);
      if (u == null || _isGoogleThumbnail(u)) continue;
      if (_looksLikeDirectImageUrl(u)) _offerGoogleUrl(u, urls);
    }
  }

  static bool _isGoogleThumbnail(String url) {
    final lower = url.toLowerCase();
    return lower.contains('=s16') ||
        lower.contains('=s32') ||
        lower.contains('=w16') ||
        lower.contains('=h16') ||
        lower.contains('encrypted-tbn0.gstatic.com') ||
        lower.contains('encrypted-tbn1.gstatic.com') ||
        lower.contains('encrypted-tbn2.gstatic.com') ||
        lower.contains('encrypted-tbn3.gstatic.com') ||
        lower.contains('/imgres?') ||
        lower.contains('gstatic.com/images?q=tbn');
  }

  static bool _looksLikeDirectImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.png') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.webp') ||
        lower.contains('.gif') ||
        lower.contains('logo') ||
        lower.contains('brand') ||
        lower.contains('googleusercontent.com');
  }

  static void _collectOuFields(String chunk, Set<String> urls) {
    for (final m in RegExp(r'"ou"\s*:\s*"(https?://[^"]+)"').allMatches(chunk)) {
      _offerGoogleUrl(m.group(1), urls);
    }
  }

  static String _unescapeJsonUrl(String raw) {
    var s = raw
        .replaceAll(r'\\/', '/')
        .replaceAll(r'\/', '/')
        .replaceAll(r'\\u003d', '=')
        .replaceAll(r'\u003d', '=')
        .replaceAll(r'\\u0026', '&')
        .replaceAll(r'\u0026', '&')
        .replaceAll('&amp;', '&');
    try {
      s = Uri.decodeComponent(s);
    } catch (_) {}
    try {
      // Second pass for double-encoded imgurl= values.
      if (s.contains('%2F') || s.contains('%3A')) {
        s = Uri.decodeComponent(s);
      }
    } catch (_) {}
    return s;
  }

  static String _htmlUnescape(String raw) {
    return raw
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
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
          .get(searchUri, headers: _browserHeadersFor(searchUri))
          .timeout(_requestTimeout);
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

      await Future.wait(
        slugs.take(3).map((slug) async {
          try {
            final detailUri =
                Uri.parse('https://www.brandsoftheworld.com$slug');
            final detail = await _client
                .get(detailUri, headers: _browserHeadersFor(detailUri))
                .timeout(_requestTimeout);
            if (detail.statusCode != 200) return;
            for (final m in RegExp(
              r'https://d1yjjnpx0p53s8\.cloudfront\.net/styles/[^"''>\s]+',
            ).allMatches(detail.body)) {
              final url = m.group(0)!;
              if (!url.contains('aotw-envelope')) urls.add(url);
            }
          } catch (_) {}
        }).map((f) => f.catchError((Object _, StackTrace __) {})),
      );

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

  Future<List<LogoCandidate>> _tineyeSearch(_RelevanceContext ctx) async {
    try {
      final urls = <String>{};
      for (final q in _imageSearchQueries(ctx).take(3)) {
        try {
          final uri = Uri.https('tineye.com', '/search', {'query': q});
          final res = await _client
              .get(uri, headers: _browserHeadersFor(uri))
              .timeout(_requestTimeout);
          if (res.statusCode != 200) continue;
          for (final m in RegExp(
            r'https?://[^"''>\s]+\.(?:png|jpg|jpeg|webp)(?:[^"''>\s]*)',
          ).allMatches(res.body)) {
            final url = m.group(0)!;
            if (_isAcceptableLogoUrl(url) && !url.contains('tineye.com')) {
              urls.add(url);
            }
          }
          if (urls.length >= 12) break;
        } catch (_) {
          continue;
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
      final out = <LogoCandidate>[];
      // Try the raw name and a looser company-stripped variant.
      final searches = <String>{
        name,
        name.replaceAll(
          RegExp(
            r'\b(inc|incorporated|ltd|limited|llc|corp|corporation|co|company)\b',
            caseSensitive: false,
          ),
          '',
        ).replaceAll(RegExp(r'\s+'), ' ').trim(),
      };

      for (final term in searches) {
        if (term.isEmpty) continue;
        try {
          final searchUri = Uri.https('en.wikipedia.org', '/w/api.php', {
            'action': 'query',
            'list': 'search',
            'srsearch': term,
            'srlimit': '5',
            'format': 'json',
            'origin': '*',
          });
          final searchRes = await _client
              .get(searchUri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
              .timeout(_requestTimeout);
          if (searchRes.statusCode != 200) continue;

          final body = jsonDecode(searchRes.body);
          final hits = body['query']?['search'];
          if (hits is! List || hits.isEmpty) continue;

          for (final hit in hits.take(4)) {
            final title = '${hit['title'] ?? ''}';
            if (title.isEmpty) continue;
            final titleScore = _textRelevance(title, ctx);
            if (titleScore < 4 && !_looseNameMatch(title, ctx)) continue;

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
                .get(imgUri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
                .timeout(_requestTimeout);
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
        } catch (_) {
          continue;
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<LogoCandidate>> _duckDuckGoCandidates(_RelevanceContext ctx) async {
    try {
      final out = <LogoCandidate>[];
      for (final q in _imageSearchQueries(ctx).take(3)) {
        try {
          final uri = Uri.https('api.duckduckgo.com', '/', {
            'q': q,
            'format': 'json',
            'pretty': '0',
            'no_redirect': '1',
            'no_html': '1',
          });
          final res = await _client
              .get(uri, headers: {
                'User-Agent': _nextChromeProfile().ua,
                'Accept': 'application/json',
              })
              .timeout(_requestTimeout);
          if (res.statusCode != 200) continue;

          final body = jsonDecode(res.body);
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

          // Official website from Instant Answer — useful domain signal.
          final absUrl = '${body['AbstractURL'] ?? ''}';
          final absDomain = _normalizeDomain(absUrl);
          if (absDomain.isNotEmpty) {
            out.add(
              LogoCandidate(
                url: 'https://logo.clearbit.com/$absDomain',
                source: 'DuckDuckGo → Clearbit ($absDomain)',
                score: _scoreDomainApi(absDomain, 'Clearbit', ctx) + 4,
              ),
            );
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
          if (out.length >= 8) break;
        } catch (_) {
          continue;
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// DuckDuckGo image HTML endpoint — often less aggressive than Google blocking.
  Future<List<LogoCandidate>> _duckDuckGoImageSearch(_RelevanceContext ctx) async {
    try {
      final urls = <String>{};
      final primary = _queriesForSearch(ctx, expanded: false, includePrimary: true);
      final expanded = _queriesForSearch(ctx, expanded: true);

      Future<void> runQueries(List<String> queries) async {
        for (final q in queries) {
          if (urls.length >= 24) break;
          try {
            final uri = Uri.https('duckduckgo.com', '/', {
              'q': q,
              'iax': 'images',
              'ia': 'images',
            });
            final res = await _client
                .get(uri, headers: _browserHeadersFor(uri))
                .timeout(_requestTimeout);
            if (res.statusCode != 200) continue;

            // vqd token unlocks the i.js JSON feed.
            final vqdMatch =
                RegExp(r'''vqd=['"]([^'"]+)['"]''').firstMatch(res.body) ??
                    RegExp(r'vqd=([0-9-]+)').firstMatch(res.body);
            final vqd = vqdMatch?.group(1);
            if (vqd != null && vqd.isNotEmpty) {
              final feed = Uri.https('duckduckgo.com', '/i.js', {
                'l': 'us-en',
                'o': 'json',
                'q': q,
                'vqd': vqd,
                'f': ',,,',
                'p': '1',
              });
              final feedHeaders = _browserHeadersRotating(referer: uri.toString())
                ..addAll({
                  'Accept': 'application/json,text/javascript,*/*;q=0.8',
                  'Sec-Fetch-Dest': 'empty',
                  'Sec-Fetch-Mode': 'cors',
                  'Sec-Fetch-Site': 'same-origin',
                });
              final feedRes = await _client
                  .get(feed, headers: feedHeaders)
                  .timeout(_requestTimeout);
              if (feedRes.statusCode == 200) {
                try {
                  final body = jsonDecode(feedRes.body);
                  final results = body is Map ? body['results'] : null;
                  if (results is List) {
                    for (final item in results.take(35)) {
                      if (item is! Map) continue;
                      for (final key in ['image', 'url']) {
                        final image = '${item[key] ?? ''}';
                        if (image.startsWith('http')) urls.add(image);
                      }
                    }
                  }
                } catch (_) {}
              }
            }

            for (final m in RegExp(
              r'https?://[^\s"<>]+\.(?:png|jpe?g|webp)(?:\?[^\s"<>]*)?',
            ).allMatches(res.body)) {
              final u = m.group(0)!;
              if (!_isGoogleThumbnail(u)) urls.add(u);
            }
          } catch (_) {
            continue;
          }
        }
      }

      await runQueries(primary);
      if (urls.isEmpty) {
        await runQueries(expanded);
      } else if (urls.length < 6) {
        await runQueries(expanded.take(3).toList());
      }

      return _urlCandidatesFromSet(
        urls,
        source: 'DuckDuckGo Images',
        ctx: ctx,
        sourceBonus: 8,
        minScore: 24,
      );
    } catch (_) {
      return const [];
    }
  }

  static bool _looseNameMatch(String text, _RelevanceContext ctx) {
    final hay = text.toLowerCase();
    for (final token in ctx.tokens) {
      if (token.length >= 4 && hay.contains(token)) return true;
    }
    final name = ctx.companyName.toLowerCase().trim();
    return name.isNotEmpty && hay.contains(name);
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
      case 'DuckDuckGo Images':
        score += 5;
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
            headers: _imageDownloadHeaders(uri),
          )
          .timeout(_requestTimeout);
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

  /// Prefer an explicit domain, then guessed TLDs, then DuckDuckGo Instant Answer.
  Future<List<String>> _resolveDomains(String name, String dom) async {
    final guessed = _guessDomains(name);
    final domains = <String>[
      if (dom.isNotEmpty) dom,
      ...guessed,
    ];

    if (name.isNotEmpty) {
      try {
        final resolved = await _resolveDomainFromDuckDuckGo(name);
        if (resolved != null &&
            resolved.isNotEmpty &&
            _domainLooksCorporate(resolved, name)) {
          // Insert after an explicit user domain, ahead of pure guesses.
          domains.insert(dom.isNotEmpty ? 1 : 0, resolved);
        }
      } catch (_) {}
    }

    final seen = <String>{};
    return [
      for (final d in domains)
        if (d.isNotEmpty && seen.add(d)) d,
    ];
  }

  Future<String?> _resolveDomainFromDuckDuckGo(String companyName) async {
    try {
      final uri = Uri.https('api.duckduckgo.com', '/', {
        'q': '$companyName company',
        'format': 'json',
        'no_redirect': '1',
        'no_html': '1',
      });
      final res = await _client
          .get(uri, headers: {
            'User-Agent': _nextChromeProfile().ua,
            'Accept': 'application/json',
          })
          .timeout(_requestTimeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;

      for (final key in ['AbstractURL', 'Redirect', 'OfficialWebsite']) {
        final domain = _normalizeDomain('${body[key] ?? ''}');
        if (domain.isNotEmpty && _domainLooksCorporate(domain, companyName)) {
          return domain;
        }
      }

      final related = body['RelatedTopics'];
      if (related is List) {
        for (final item in related.take(8)) {
          if (item is! Map) continue;
          final firstUrl = '${item['FirstURL'] ?? ''}';
          final domain = _normalizeDomain(firstUrl);
          if (domain.isEmpty) continue;
          if (_domainLooksCorporate(domain, companyName)) return domain;
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _domainLooksCorporate(String domain, String companyName) {
    final host = domain.toLowerCase();
    const blocked = [
      'wikipedia.org',
      'wikidata.org',
      'wikimedia.org',
      'facebook.com',
      'linkedin.com',
      'twitter.com',
      'x.com',
      'instagram.com',
      'youtube.com',
      'bloomberg.com',
      'reuters.com',
      'crunchbase.com',
      'glassdoor.',
      'indeed.com',
    ];
    for (final b in blocked) {
      if (host.contains(b)) return false;
    }
    final tokens = _companyTokens(companyName);
    final stem = host.split('.').first;
    for (final t in tokens) {
      if (t.length >= 4 && (stem.contains(t) || t.contains(stem))) return true;
    }
    // Allow unknown corporate hosts only when no tokens to compare.
    return tokens.isEmpty;
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
      '.energy',
      '.oil',
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
      out.add('${words.first}.ca');
    } else if (words.length == 1 && words.first.length >= 3) {
      // Single-token companies (e.g. Keyera) — prioritize common corporate TLDs.
      out.add('${words.first}.com');
      out.add('${words.first}.ca');
      out.add('${words.first}.net');
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
