import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Minimal client for YouTube's internal "InnerTube" API (the same API that
/// www.youtube.com uses). When [cookies] are set (after Google sign-in) every
/// request is authenticated as that account, so Home, Subscriptions, History,
/// likes and subscribing all act on the real YouTube account.
class InnerTube {
  static final InnerTube instance = InnerTube._();
  InnerTube._();

  static const String origin = 'https://www.youtube.com';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  static const String _fallbackClientVersion = '2.20261030.02.00';

  final http.Client _http = http.Client();

  String? _cookies;
  String? _clientVersion;
  String? _visitorData;
  Future<void>? _configLoading;

  String hl = 'en';
  String gl = 'US';

  /// OAuth access token source when signed in through the browser
  /// (see google_oauth.dart). Used when there are no session cookies.
  Future<String?> Function()? accessToken;
  bool Function() hasOAuthSession = () => false;

  bool get isSignedIn =>
      _cookieValue('SAPISID') != null || _cookieValue('__Secure-3PAPISID') != null || hasOAuthSession();

  /// Call after signing in or out through the browser so session-bound
  /// config is fetched again.
  void resetConfig() {
    _clientVersion = null;
    _visitorData = null;
    _configLoading = null;
  }

  /// Set the raw `Cookie` header captured from the sign-in WebView (or null to sign out).
  void setCookies(String? cookies) {
    _cookies = (cookies == null || cookies.trim().isEmpty) ? null : cookies.trim();
    // Visitor data / client version are tied to the session; reload them.
    _clientVersion = null;
    _visitorData = null;
    _configLoading = null;
  }

  String? _cookieValue(String name) {
    final raw = _cookies;
    if (raw == null) return null;
    for (final part in raw.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      if (part.substring(0, idx).trim() == name) return part.substring(idx + 1).trim();
    }
    return null;
  }

  String _hash(int ts, String secret) =>
      '${ts}_${sha1.convert(utf8.encode('$ts $secret $origin'))}';

  /// SAPISIDHASH authorization, the scheme youtube.com uses for logged-in API calls.
  String? _authorization() {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final parts = <String>[];
    final sapisid = _cookieValue('SAPISID') ?? _cookieValue('__Secure-3PAPISID');
    if (sapisid != null) parts.add('SAPISIDHASH ${_hash(ts, sapisid)}');
    final p1 = _cookieValue('__Secure-1PAPISID');
    if (p1 != null) parts.add('SAPISID1PHASH ${_hash(ts, p1)}');
    final p3 = _cookieValue('__Secure-3PAPISID');
    if (p3 != null) parts.add('SAPISID3PHASH ${_hash(ts, p3)}');
    return parts.isEmpty ? null : parts.join(' ');
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept-Language': '$hl-$gl,$hl;q=0.9',
      'Origin': origin,
      'Referer': '$origin/',
      'X-Origin': origin,
    };
    if (_cookies != null) {
      headers['Cookie'] = _cookies!;
      final auth = _authorization();
      if (auth != null) {
        headers['Authorization'] = auth;
        headers['X-Goog-AuthUser'] = '0';
      }
    }
    return headers;
  }

  /// Reads the current web client version (and visitor id) from the youtube.com page.
  Future<void> _ensureConfig() {
    if (_clientVersion != null) return Future.value();
    return _configLoading ??= () async {
      try {
        final res = await _http
            .get(Uri.parse('$origin/?hl=$hl&gl=$gl'), headers: _headers())
            .timeout(const Duration(seconds: 10));
        final body = res.body;
        _clientVersion = RegExp(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"').firstMatch(body)?.group(1);
        _visitorData = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(body)?.group(1);
      } catch (_) {}
      _clientVersion ??= _fallbackClientVersion;
      _configLoading = null;
    }();
  }

  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body) async {
    await _ensureConfig();
    final headers = _headers()
      ..['Content-Type'] = 'application/json'
      ..['X-Youtube-Client-Name'] = '1'
      ..['X-Youtube-Client-Version'] = _clientVersion!;
    if (_visitorData != null) headers['X-Goog-Visitor-Id'] = _visitorData!;
    if (_cookies == null && hasOAuthSession() && accessToken != null) {
      final token = await accessToken!();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }

    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': _clientVersion,
          'hl': hl,
          'gl': gl,
          'visitorData': ?_visitorData,
        },
        'user': {'lockedSafetyMode': false},
      },
      ...body,
    };

    final res = await _http
        .post(
          Uri.parse('$origin/youtubei/v1/$endpoint?prettyPrint=false'),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw InnerTubeException(endpoint, res.statusCode);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> browse({String? browseId, String? params, String? continuation}) =>
      post('browse', {
        'browseId': ?browseId,
        'params': ?params,
        'continuation': ?continuation,
      });

  Future<Map<String, dynamic>> search({String? query, String? params, String? continuation}) =>
      post('search', {
        'query': ?query,
        'params': ?params,
        'continuation': ?continuation,
      });

  Future<Map<String, dynamic>> next({String? videoId, String? continuation}) => post('next', {
        'videoId': ?videoId,
        'continuation': ?continuation,
      });

  Future<Map<String, dynamic>> resolveUrl(String url) =>
      post('navigation/resolve_url', {'url': url});

  Future<Map<String, dynamic>> accountMenu() => post('account/account_menu', {});

  Future<void> subscribe(String channelId, {required bool subscribe}) =>
      post(subscribe ? 'subscription/subscribe' : 'subscription/unsubscribe', {
        'channelIds': [channelId],
      });

  Future<void> like(String videoId, {required bool like}) =>
      post(like ? 'like/like' : 'like/removelike', {
        'target': {'videoId': videoId},
      });

  Future<List<String>> suggestions(String query) async {
    final uri = Uri.parse('https://suggestqueries.google.com/complete/search').replace(
      queryParameters: {'client': 'firefox', 'ds': 'yt', 'hl': hl, 'gl': gl, 'q': query},
    );
    final res = await _http.get(uri, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is List && data.length > 1 && data[1] is List) {
      return List<String>.from((data[1] as List).map((e) => e.toString()));
    }
    return [];
  }
}

class InnerTubeException implements Exception {
  final String endpoint;
  final int statusCode;
  InnerTubeException(this.endpoint, this.statusCode);

  @override
  String toString() => 'YouTube request "$endpoint" failed (HTTP $statusCode)';
}
