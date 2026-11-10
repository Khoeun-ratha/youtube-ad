import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/library_provider.dart';
import '../services/google_oauth.dart';

/// Google sign-in inside the app. It opens Google's "Choose an account" page:
/// the first time it asks for an email (like any new browser); afterwards it
/// lists the accounts already used here, so signing in is one tap. Once Google
/// redirects back to youtube.com we keep the session cookies and close.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // A regular mobile Chrome user agent: Google refuses to sign in inside
  // WebViews that identify themselves as such ("; wv").
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
  static const _continue =
      'https://www.youtube.com/signin?action_handle_signin=true&app=m&next=%2F';
  static final _loginUrl = Uri.https('accounts.google.com', '/AccountChooser', {
    'service': 'youtube',
    'uilel': '3',
    'hl': 'en',
    'continue': _continue,
  });

  late final WebViewController _controller;
  bool _loading = true;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_userAgent)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: _onPageFinished,
      ))
      ..loadRequest(_loginUrl);
  }

  Future<void> _onPageFinished(String url) async {
    if (mounted) setState(() => _loading = false);
    final host = Uri.tryParse(url)?.host ?? '';
    if (_finishing || !host.endsWith('youtube.com')) return;

    _finishing = true;
    final ok = await context.read<AuthProvider>().completeSignIn();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _finishing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in with Google'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

/// Reloads everything that depends on the account after signing in/out.
Future<void> onSignedIn(BuildContext context) async {
  context.read<FeedProvider>().reset();
  context.read<LibraryProvider>().loadAll();
}

/// "Sign in" button. Uses the in-app Google page; if a Google OAuth client ID
/// is configured (google_oauth.dart) it signs in through the browser instead.
class SignInButton extends StatefulWidget {
  final VoidCallback? onSignedIn;

  const SignInButton({super.key, this.onSignedIn});

  @override
  State<SignInButton> createState() => _SignInButtonState();
}

class _SignInButtonState extends State<SignInButton> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final bool ok;
      if (GoogleOAuth.isConfigured) {
        ok = await context.read<AuthProvider>().signInWithGoogle();
      } else {
        ok = await Navigator.of(context, rootNavigator: true).push<bool>(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ) ==
            true;
      }
      if (ok) widget.onSignedIn?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF3EA6FF),
        side: const BorderSide(color: AppColors.divider),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      icon: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.account_circle_outlined),
      label: const Text('Sign in'),
      onPressed: _busy ? null : _signIn,
    );
  }
}
