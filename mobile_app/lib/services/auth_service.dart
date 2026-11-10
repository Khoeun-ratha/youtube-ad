import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_oauth.dart';
import 'innertube.dart';

/// Keeps the youtube.com session cookies captured after Google sign-in and
/// hands them to [InnerTube] so every API call runs as the signed-in account.
class AuthService {
  static const MethodChannel _cookieChannel = MethodChannel('com.adfree.youtube/cookies');
  static const _keyCookies = 'auth_youtube_cookies';

  /// Loads a saved session (call once at startup).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    InnerTube.instance.setCookies(prefs.getString(_keyCookies));
    await GoogleOAuth.init();
    InnerTube.instance
      ..accessToken = GoogleOAuth.accessToken
      ..hasOAuthSession = (() => GoogleOAuth.isSignedIn);
  }

  /// "Sign in with Google" in the browser (account chooser). Returns true
  /// when signed in, false when the user backed out.
  static Future<bool> signInWithBrowser() async {
    final ok = await GoogleOAuth.signIn();
    if (ok) InnerTube.instance.resetConfig();
    return ok;
  }

  static bool get isSignedIn => InnerTube.instance.isSignedIn;

  /// Reads youtube.com cookies from the WebView cookie store. Returns true once
  /// the Google login has produced a YouTube session (SAPISID cookie present).
  static Future<bool> captureSessionFromWebView() async {
    try {
      final cookies = await _cookieChannel.invokeMethod<String>('get', {'url': 'https://www.youtube.com'});
      if (cookies == null || !cookies.contains('SAPISID=')) return false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCookies, cookies);
      InnerTube.instance.setCookies(cookies);
      return true;
    } catch (e) {
      debugPrint('Cookie capture failed: $e');
      return false;
    }
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCookies);
    InnerTube.instance.setCookies(null);
    await GoogleOAuth.signOut();
    try {
      // Only the YouTube session is removed. Google's own cookies stay, so the
      // next sign-in shows the "Choose an account" list instead of an email box.
      await _cookieChannel.invokeMethod('clearYouTube');
    } catch (_) {}
  }
}
