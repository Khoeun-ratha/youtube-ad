import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// "Sign in with Google" through the phone's browser (Chrome Custom Tab), the
/// same flow websites use: Chrome shows the "Choose an account" list of the
/// Google accounts already on the phone, then Google redirects back into the
/// app with an authorization code (OAuth 2.0 + PKCE, no client secret).
///
/// Setup (Google Cloud Console -> APIs & Services):
///  1. Enable "YouTube Data API v3".
///  2. OAuth consent screen: add the scope `.../auth/youtube` and your Google
///     accounts as test users.
///  3. Credentials -> Create OAuth client ID -> type **Android**,
///     package `com.adfree.youtube.mobile_app`, SHA-1 of the signing key,
///     then Advanced settings -> enable **Custom URI scheme**.
///  4. Paste the client ID into [androidClientId].
///
/// iOS (signs in through an ASWebAuthenticationSession Safari sheet):
///  5. Credentials -> Create OAuth client ID -> type **iOS**, bundle ID
///     `com.adfree.youtube.mobileApp`, and paste it into [iosClientId].
///     Its redirect is the reversed client ID
///     (`com.googleusercontent.apps.<id>:/oauth2redirect`), worked out below.
class GoogleOAuth {
  static const String androidClientId = ''; // e.g. 1234-abcd.apps.googleusercontent.com
  static const String iosClientId = ''; // e.g. 1234-efgh.apps.googleusercontent.com

  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String get clientId => _isIOS ? iosClientId : androidClientId;

  /// Custom URL scheme Google redirects to after sign-in.
  static String get redirectScheme {
    if (!_isIOS) return 'com.adfree.youtube.mobile_app';
    const suffix = '.apps.googleusercontent.com';
    final id = iosClientId.endsWith(suffix)
        ? iosClientId.substring(0, iosClientId.length - suffix.length)
        : iosClientId;
    return 'com.googleusercontent.apps.$id';
  }

  static String get redirectUri => '$redirectScheme:/oauth2redirect';
  static const List<String> scopes = [
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/youtube',
  ];

  static const MethodChannel _channel = MethodChannel('com.adfree.youtube/oauth');
  static const _keyRefresh = 'oauth_refresh_token';

  static String? _refreshToken;
  static String? _accessToken;
  static DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  static Completer<Uri>? _pending;
  static Future<String?>? _refreshing;

  static bool get isConfigured => clientId.isNotEmpty;
  static bool get isSignedIn => _refreshToken != null;

  /// Restores a saved session and starts listening for the browser redirect.
  static Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'redirect') _deliver(call.arguments as String?);
    });
    final prefs = await SharedPreferences.getInstance();
    _refreshToken = prefs.getString(_keyRefresh);
  }

  static void _deliver(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    final pending = _pending;
    if (uri == null || pending == null || pending.isCompleted) return;
    pending.complete(uri);
  }

  /// Opens Google's account chooser in the browser and waits until the user
  /// comes back. Returns true when the app is signed in.
  static Future<bool> signIn() async {
    if (!isConfigured) {
      throw OAuthException('Google sign-in is not set up: GoogleOAuth.'
          '${_isIOS ? 'iosClientId' : 'androidClientId'} is empty.');
    }
    final verifier = _randomString(64);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _randomString(24);

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes.join(' '),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'prompt': 'select_account',
      'access_type': 'offline',
    });

    _deliver('$redirectUri?error=access_denied'); // drop an earlier, unfinished attempt
    _pending = Completer<Uri>();
    // The native side reports back the redirect URL, or `<redirectUri>?error=
    // access_denied` when the user closes the browser without finishing.
    await _channel.invokeMethod('open', {'url': authUrl.toString(), 'scheme': redirectScheme});

    final result = await _pending!.future;
    _pending = null;

    final params = result.queryParameters;
    if (params['error'] != null) {
      if (params['error'] == 'access_denied') return false;
      throw OAuthException('Google returned an error: ${params['error']}');
    }
    if (params['state'] != state || params['code'] == null) {
      throw const OAuthException('Sign-in response did not match the request.');
    }

    final tokens = await _tokenRequest({
      'grant_type': 'authorization_code',
      'code': params['code']!,
      'code_verifier': verifier,
      'redirect_uri': redirectUri,
    });
    final refresh = tokens['refresh_token'] as String?;
    if (refresh == null) throw const OAuthException('Google did not return a refresh token.');
    _refreshToken = refresh;
    _store(tokens);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRefresh, refresh);
    return true;
  }

  /// A valid access token, refreshed when it is about to expire.
  static Future<String?> accessToken() {
    if (_refreshToken == null) return Future.value(null);
    if (_accessToken != null && DateTime.now().isBefore(_expiresAt)) return Future.value(_accessToken);
    return _refreshing ??= () async {
      try {
        final tokens = await _tokenRequest({
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken!,
        });
        _store(tokens);
        return _accessToken;
      } on OAuthException catch (e) {
        // Only a revoked/expired refresh token ends the session. Server or
        // network hiccups keep the user signed in; we retry on the next request.
        if (e.code == 'invalid_grant') await signOut(revoke: false);
        return null;
      } catch (_) {
        return null; // offline etc.; stay signed in and retry later
      } finally {
        _refreshing = null;
      }
    }();
  }

  static Future<void> signOut({bool revoke = true}) async {
    final token = _refreshToken;
    _refreshToken = null;
    _accessToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRefresh);
    if (revoke && token != null) {
      try {
        await http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': token});
      } catch (_) {}
    }
  }

  static void _store(Map<String, dynamic> tokens) {
    _accessToken = tokens['access_token'] as String?;
    final expiresIn = (tokens['expires_in'] as num?)?.toInt() ?? 3600;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));
  }

  static Future<Map<String, dynamic>> _tokenRequest(Map<String, String> body) async {
    final res = await http
        .post(Uri.parse('https://oauth2.googleapis.com/token'), body: {'client_id': clientId, ...body})
        .timeout(const Duration(seconds: 20));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw OAuthException('Token request failed: ${data['error_description'] ?? data['error']}',
          code: data['error'] as String?);
    }
    return data;
  }

  static String _randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}

class OAuthException implements Exception {
  final String message;
  final String? code; // OAuth error code, e.g. "invalid_grant"
  const OAuthException(this.message, {this.code});
  @override
  String toString() => message;
}
