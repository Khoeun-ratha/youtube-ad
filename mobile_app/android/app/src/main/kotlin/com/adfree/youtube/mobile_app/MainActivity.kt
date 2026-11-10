package com.adfree.youtube.mobile_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebView
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // True while a video is playing (set from Dart through the wakelock channel).
    private var playing = false
    private var resumed = false
    private val handler = Handler(Looper.getMainLooper())
    private val stopServiceLater = Runnable { stopPlaybackService() }
    private var askedNotifications = false
    private val CHANNEL = "com.adfree.youtube/wakelock"
    private val OAUTH_CHANNEL = "com.adfree.youtube/oauth"
    private val OAUTH_SCHEME = "com.adfree.youtube.mobile_app"

    private var oauthChannel: MethodChannel? = null
    // Google sign-in runs in a Chrome Custom Tab; these track whether we are
    // waiting for it so closing the tab without signing in can be reported.
    private var oauthInProgress = false
    private var oauthLeftApp = false
    private val COOKIE_CHANNEL = "com.adfree.youtube/cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    onPlaybackStarted()
                    result.success(true)
                }
                "release" -> {
                    onPlaybackStopped()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Google sign-in happens in a WebView; this reads the resulting youtube.com
        // session cookies (including HttpOnly ones, which JavaScript cannot see).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COOKIE_CHANNEL).setMethodCallHandler { call, result ->
            val cookies = CookieManager.getInstance()
            when (call.method) {
                "get" -> result.success(cookies.getCookie(call.argument<String>("url") ?: "https://www.youtube.com"))
                "clearYouTube" -> {
                    // Expire every youtube.com cookie (host-only and domain ones),
                    // leaving accounts.google.com's remembered accounts in place.
                    for (url in listOf("https://www.youtube.com", "https://m.youtube.com", "https://youtube.com")) {
                        val raw = cookies.getCookie(url) ?: continue
                        for (part in raw.split(";")) {
                            val name = part.substringBefore("=").trim()
                            if (name.isEmpty()) continue
                            cookies.setCookie(url, "$name=; Max-Age=0; Path=/; Secure")
                            cookies.setCookie(url, "$name=; Max-Age=0; Path=/; Secure; Domain=.youtube.com")
                        }
                    }
                    cookies.flush()
                    result.success(true)
                }
                "clear" -> {
                    cookies.removeAllCookies { removed ->
                        cookies.flush()
                        result.success(removed)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // "Sign in with Google" in the browser: open the Google account chooser
        // in a Custom Tab; Google redirects to com.adfree.youtube.mobile_app:/oauth2redirect,
        // which Android routes back here (onNewIntent).
        oauthChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OAUTH_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("bad_args", "url missing", null)
                        } else {
                            oauthInProgress = true
                            oauthLeftApp = false
                            openInBrowser(Uri.parse(url))
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun openInBrowser(uri: Uri) {
        try {
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(this, uri)
        } catch (e: Exception) {
            // No Custom Tabs browser: fall back to any browser.
            startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val data = intent.data
        if (data != null && data.scheme == OAUTH_SCHEME) {
            oauthInProgress = false
            oauthChannel?.invokeMethod("redirect", data.toString())
        }
    }

    override fun onPause() {
        super.onPause()
        resumed = false
        if (oauthInProgress) oauthLeftApp = true
        // Locking the screen pauses the activity first; keep the video going.
        if (playing) keepPlayingInBackground()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        if (!playing) {
            handler.removeCallbacks(stopServiceLater)
            stopPlaybackService()
        }
        // Back in the app without a redirect: the user closed the browser.
        if (oauthInProgress && oauthLeftApp) {
            oauthInProgress = false
            oauthChannel?.invokeMethod("redirect", "$OAUTH_SCHEME:/oauth2redirect?error=access_denied")
        }
    }

    private fun onPlaybackStarted() {
        playing = true
        handler.removeCallbacks(stopServiceLater)
        startPlaybackService()
        if (!resumed) keepPlayingInBackground()
    }

    private fun onPlaybackStopped() {
        playing = false
        handler.removeCallbacks(stopServiceLater)
        // Paused while in the app: nothing to keep alive. Paused in the
        // background (lock screen, buffering hiccup): keep the service a while
        // so playback can resume without being frozen.
        if (resumed) stopPlaybackService() else handler.postDelayed(stopServiceLater, 5 * 60 * 1000L)
    }

    private fun startPlaybackService() {
        askForNotifications()
        try {
            val intent = Intent(this, PlaybackService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
        } catch (e: Exception) {
            // Android doesn't allow starting it from the background; it is
            // normally already running by then.
            e.printStackTrace()
        }
    }

    private fun stopPlaybackService() {
        try {
            stopService(Intent(this, PlaybackService::class.java))
        } catch (_: Exception) {}
    }

    // Android 13+: the background-play notification needs permission to show.
    private fun askForNotifications() {
        if (askedNotifications || !resumed || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        askedNotifications = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
        }
    }

    // Videos play in a WebView (YouTube's own player). Android tells a WebView
    // it is hidden when the app goes to the background or the screen locks,
    // which suspends its media; while something is playing, tell it it's still
    // visible so playback keeps going. Repeated a few times because the
    // embedding hides it again in steps (pause, stop, surface teardown).
    private fun keepPlayingInBackground() {
        for (delay in longArrayOf(0L, 300L, 1000L, 2500L)) {
            handler.postDelayed({ if (playing && !resumed) keepWebViewsVisible(window.decorView) }, delay)
        }
    }

    override fun onStop() {
        super.onStop()
        if (playing) keepPlayingInBackground()
    }

    private fun keepWebViewsVisible(view: View) {
        if (view is WebView) {
            view.dispatchWindowVisibilityChanged(View.VISIBLE)
            view.onResume()
            view.resumeTimers()
            return
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) keepWebViewsVisible(view.getChildAt(i))
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        stopPlaybackService()
        super.onDestroy()
    }
}
