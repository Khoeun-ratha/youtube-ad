import 'package:flutter/material.dart';
import '../models/video_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  AccountInfo? _account;

  bool get isSignedIn => AuthService.isSignedIn;
  AccountInfo? get account => _account;

  AuthProvider() {
    if (isSignedIn) loadAccount();
  }

  Future<void> loadAccount() async {
    _account = await _apiService.getAccountInfo();
    notifyListeners();
  }

  /// Called by the in-app sign-in screen after Google redirects back to YouTube.
  Future<bool> completeSignIn() async {
    final ok = await AuthService.captureSessionFromWebView();
    if (ok) await loadAccount();
    notifyListeners();
    return ok;
  }

  /// Opens Google's account chooser in the browser; returns when the user
  /// comes back to the app. Throws [OAuthException] on a setup/token error.
  Future<bool> signInWithGoogle() async {
    final ok = await AuthService.signInWithBrowser();
    if (ok) await loadAccount();
    notifyListeners();
    return ok;
  }

  Future<void> signOut() async {
    await AuthService.signOut();
    _account = null;
    notifyListeners();
  }
}
