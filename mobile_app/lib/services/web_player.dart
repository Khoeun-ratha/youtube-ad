import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Plays videos with YouTube's own mobile web player, with ads removed.
///
/// YouTube now only serves most videos through its web/app players (SABR
/// streaming + PO tokens), so raw stream URLs get 403 after the first few MB.
/// Playing through m.youtube.com always works, uses the signed-in cookies and
/// records watch history. Ads are removed before the player ever sees them:
/// the ad fields are pruned from every player response, ad requests are
/// blocked, and anything that slips through is skipped and muted.
class WebPlayer extends ChangeNotifier {
  InAppWebViewController? _controller;
  String? _videoId;
  Duration? _pendingStart;

  bool _playing = false;
  bool _buffering = false;
  bool _hasStarted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<String> _qualities = const [];
  String _quality = 'auto';
  bool _audioOnly = false;
  double _rate = 1.0;

  final _ended = StreamController<void>.broadcast();

  /// Called when the page moves to another video by itself (e.g. the user
  /// tapped a video inside the player).
  void Function(String videoId)? onNavigated;

  String? get videoId => _videoId;
  bool get isPlaying => _playing;
  bool get isBuffering => _buffering;

  /// True once the current video has actually started playing.
  bool get hasStarted => _hasStarted;
  Duration get position => _position;
  Duration get duration => _duration;
  double get rate => _rate;
  Stream<void> get onEnded => _ended.stream;

  /// Quality labels the current video offers, best first ("1080p", "720p", ...).
  List<String> get qualities => [for (final q in _qualities) qualityLabel(q)];

  static const _labels = {
    'hd2160': '2160p',
    'hd1440': '1440p',
    'hd1080': '1080p',
    'hd720': '720p',
    'large': '480p',
    'medium': '360p',
    'small': '240p',
    'tiny': '144p',
  };

  static String qualityLabel(String code) => _labels[code] ?? code;

  static String qualityCode(String label) {
    if (label == 'Auto') return 'auto';
    return _labels.entries.where((e) => e.value == label).firstOrNull?.key ?? 'auto';
  }

  /// The quality actually asked of YouTube (lowest while audio-only).
  String get _effectiveQuality => _audioOnly ? 'tiny' : _quality;

  Future<void> load(String videoId, {Duration? startAt, String quality = 'Auto'}) async {
    _videoId = videoId;
    _pendingStart = startAt;
    _quality = qualityCode(quality);
    _resetState();
    // Without a live web view yet, it loads the video when it is created.
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(_watchUrl(videoId, startAt))));
  }

  String _watchUrl(String id, Duration? start) {
    final t = start != null && start.inSeconds > 0 ? '&t=${start.inSeconds}s' : '';
    return 'https://m.youtube.com/watch?v=$id$t';
  }

  void _resetState() {
    _playing = false;
    _buffering = true;
    _hasStarted = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _qualities = const [];
    notifyListeners();
  }

  Future<void> stop() async {
    _videoId = null;
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    _resetState();
    _buffering = false;
    notifyListeners();
  }

  Future<void> play() => _js('window.__adfree.play()');

  Future<void> pause() => _js('window.__adfree.pause()');

  Future<void> playOrPause() => _playing ? pause() : play();

  Future<void> seek(Duration to) => _js('window.__adfree.seek(${to.inMilliseconds / 1000})');

  Future<void> setRate(double rate) async {
    _rate = rate;
    await _js('window.__adfree.rate($rate)');
    notifyListeners();
  }

  Future<void> setQuality(String label) async {
    _quality = qualityCode(label);
    await _js('window.__adfree.quality(${jsonEncode(_effectiveQuality)})');
  }

  /// Saves data while only the sound is wanted; kept for later videos too.
  Future<void> setAudioOnly(bool audioOnly) async {
    _audioOnly = audioOnly;
    await _js('window.__adfree.quality(${jsonEncode(_effectiveQuality)})');
  }

  /// Re-applies the quality and speed to a freshly loaded page.
  void _applySettings(InAppWebViewController c) {
    final q = _effectiveQuality;
    final parts = [
      if (q != 'auto') 'window.__adfree.quality(${jsonEncode(q)});',
      if (_rate != 1.0) 'window.__adfree.rate($_rate);',
    ];
    if (parts.isEmpty) return;
    c.evaluateJavascript(source: 'try { ${parts.join(' ')} } catch (e) {}').catchError((_) => null);
  }

  Future<void> _js(String source) async {
    try {
      await _controller?.evaluateJavascript(source: 'try { $source } catch (e) {}');
    } catch (_) {}
  }

  void _attach(InAppWebViewController c) {
    _controller = c;
    c.addJavaScriptHandler(
      handlerName: 'state',
      callback: (args) {
        if (args.isEmpty) return;
        _onState(jsonDecode(args.first as String) as Map<String, dynamic>);
      },
    );
    final id = _videoId;
    if (id != null) c.loadUrl(urlRequest: URLRequest(url: WebUri(_watchUrl(id, _pendingStart))));
  }

  void _detach(InAppWebViewController c) {
    if (_controller == c) _controller = null;
  }

  void _onState(Map<String, dynamic> s) {
    if (s['v'] != null && s['v'] != _videoId) return;
    final playing = s['p'] == true && s['ad'] != true;
    _playing = playing;
    _buffering = s['b'] == true || s['ad'] == true;
    if (playing) _hasStarted = true;
    _position = Duration(milliseconds: ((s['t'] as num? ?? 0) * 1000).round());
    _duration = Duration(milliseconds: ((s['d'] as num? ?? 0) * 1000).round());
    _qualities = [for (final q in (s['q'] as List? ?? const [])) if (q != 'auto') q as String];
    notifyListeners();
    if (s['e'] == true) _ended.add(null);
  }

  void _onUrlChanged(InAppWebViewController c, Uri? url) {
    if (url == null || !url.host.contains('youtube.com')) return;
    final id = url.queryParameters['v'] ??
        (url.pathSegments.length > 1 && url.pathSegments.first == 'shorts' ? url.pathSegments[1] : null);
    if (id == null) {
      // Anything other than a watch page (channel, home, ...) isn't for this view.
      if (_videoId != null && url.path != '/watch') c.goBack();
      return;
    }
    if (id != _videoId) {
      _videoId = id;
      _resetState();
      onNavigated?.call(id);
    }
  }

  @override
  void dispose() {
    _ended.close();
    super.dispose();
  }
}

/// The web view that shows a [WebPlayer]'s video, filling its box.
class YouTubeWebView extends StatefulWidget {
  final WebPlayer player;

  /// Crop to fill (Shorts) instead of letterboxing.
  final bool cover;

  /// Hide YouTube's own controls (the app draws its own).
  final bool bare;

  const YouTubeWebView({super.key, required this.player, this.cover = false, this.bare = false});

  @override
  State<YouTubeWebView> createState() => _YouTubeWebViewState();
}

class _YouTubeWebViewState extends State<YouTubeWebView> {
  InAppWebViewController? _controller;

  WebPlayer get player => widget.player;

  @override
  void dispose() {
    // Later calls must not go to a web view that no longer exists.
    final c = _controller;
    if (c != null) player._detach(c);
    super.dispose();
  }

  static final _blockedUrls = [
    r'.*doubleclick\.net/.*',
    r'.*googlesyndication\.com/.*',
    r'.*googleadservices\.com/.*',
    r'.*google\.com/pagead/.*',
    r'.*youtube\.com/pagead/.*',
    r'.*youtube\.com/api/stats/ads.*',
    r'.*youtube\.com/get_midroll_.*',
    r'.*youtube\.com/ptracking.*',
    r'.*imasdk\.googleapis\.com/.*',
  ];

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        // Never tell the page it was hidden (screen lock / app in background).
        // Otherwise Chromium pauses the video itself for about a second before
        // the app can start it again.
        allowBackgroundAudioPlaying: true,
        transparentBackground: true,
        supportZoom: false,
        disableContextMenu: true,
        useShouldOverrideUrlLoading: true,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        contentBlockers: [
          for (final pattern in _blockedUrls)
            ContentBlocker(
              trigger: ContentBlockerTrigger(urlFilter: pattern),
              action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
        ],
      ),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: 'window.__adfreeFit = ${jsonEncode(widget.cover ? 'cover' : 'contain')};'
              'window.__adfreeBare = ${widget.bare};',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(source: _pageScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
      ]),
      onWebViewCreated: (c) {
        _controller = c;
        player._attach(c);
      },
      onLoadStop: (c, _) => player._applySettings(c),
      onUpdateVisitedHistory: (c, url, _) => player._onUrlChanged(c, url),
      shouldOverrideUrlLoading: (c, action) async {
        final url = action.request.url;
        // Keep the view on YouTube watch pages; no app intents or external sites.
        if (url == null || !(url.scheme == 'https' || url.scheme == 'http' || url.scheme == 'about')) {
          return NavigationActionPolicy.CANCEL;
        }
        final host = url.host;
        final allowed = host.endsWith('youtube.com') || host.endsWith('google.com') || host.isEmpty;
        return allowed ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
      },
      onEnterFullscreen: (_) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      },
      onExitFullscreen: (_) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      },
      onPermissionRequest: (_, request) async =>
          PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY),
      onCloseWindow: player._detach,
    );
  }
}

/// Injected at document start into every page the player loads.
const _pageScript = r'''
(function () {
  if (window.__adfree) return;

  // ---- Remove ads from player data before YouTube reads it.
  var AD_KEYS = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams'];
  function prune(o) {
    try {
      if (!o || typeof o !== 'object') return o;
      for (var i = 0; i < AD_KEYS.length; i++) if (AD_KEYS[i] in o) delete o[AD_KEYS[i]];
      if (o.playerResponse) prune(o.playerResponse);
      if (Array.isArray(o)) o.forEach(prune);
    } catch (e) {}
    return o;
  }
  var parse = JSON.parse;
  JSON.parse = function () { return prune(parse.apply(this, arguments)); };
  var json = Response.prototype.json;
  Response.prototype.json = function () { return json.apply(this, arguments).then(prune); };
  var initial;
  Object.defineProperty(window, 'ytInitialPlayerResponse', {
    configurable: true,
    get: function () { return initial; },
    set: function (v) { initial = prune(v); },
  });

  // ---- Keep playing when the app is in the background.
  try {
    Object.defineProperty(document, 'hidden', { get: function () { return false; } });
    Object.defineProperty(document, 'visibilityState', { get: function () { return 'visible'; } });
  } catch (e) {}
  ['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'blur'].forEach(function (n) {
    window.addEventListener(n, function (e) { e.stopImmediatePropagation(); }, true);
    document.addEventListener(n, function (e) { e.stopImmediatePropagation(); }, true);
  });

  // ---- Show only the player, filling the view.
  var css =
    'html,body{background:#000!important;overflow:hidden!important;margin:0!important}' +
    '#player-container-id,.player-container,#player,ytm-player{position:fixed!important;top:0!important;left:0!important;' +
    'right:0!important;bottom:0!important;width:100vw!important;height:100vh!important;max-height:none!important;' +
    'padding:0!important;margin:0!important;z-index:2147483646!important;background:#000!important}' +
    '.html5-video-player,.html5-video-container{width:100%!important;height:100%!important}' +
    'video{width:100%!important;height:100%!important;left:0!important;top:0!important;object-fit:' + (window.__adfreeFit || 'contain') + '!important}' +
    '.video-ads,.ytp-ad-module,.ytp-ad-overlay-container,ytm-promoted-sparkles-web-renderer,ytm-companion-ad-renderer,' +
    '.ytp-ce-element,.ytp-pause-overlay,.ytm-autonav-bar,ytm-mealbar-promo-renderer,.mealbar-promo-renderer{display:none!important}' +
    (window.__adfreeBare ? '#player-control-overlay,.player-controls-content,.ytp-chrome-top,.ytp-chrome-bottom,.ytmCuedOverlayHost{display:none!important}' : '');
  function addCss() {
    if (document.getElementById('__adfree_css')) return;
    var s = document.createElement('style');
    s.id = '__adfree_css';
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }

  var wantPlay = true;
  var userPaused = false;
  var wantQuality = 'auto';
  var userMuted = false;
  // Respect the mute button in YouTube's controls once the video is running.
  document.addEventListener('click', function (e) {
    if (e.target && e.target.closest && e.target.closest('.ytp-mute-button,.ytmVolumeButton')) userMuted = !userMuted;
  }, true);
  var appliedQuality = '';
  var last = '';

  function video() { return document.querySelector('video'); }
  function moviePlayer() { return document.getElementById('movie_player'); }
  function currentId() {
    var m = location.search.match(/[?&]v=([\w-]{11})/) || location.pathname.match(/\/shorts\/([\w-]{11})/);
    return m ? m[1] : null;
  }

  // YouTube's player pauses itself when it thinks it was resized or went out
  // of view (e.g. when the app moves it into the mini-player), and after long
  // listening ("Continue watching?"). Only let a pause through when the user
  // just touched the player, the app asked for it, or the video ended.
  var lastInput = 0;
  var appPause = false;
  ['touchstart', 'pointerdown', 'mousedown', 'keydown'].forEach(function (n) {
    window.addEventListener(n, function () { lastInput = Date.now(); }, true);
  });
  var origPause = HTMLMediaElement.prototype.pause;
  var allowedPauseAt = 0;
  HTMLMediaElement.prototype.pause = function () {
    if (appPause || this.ended || Date.now() - lastInput < 1500 || document.querySelector('.ad-showing')) {
      allowedPauseAt = Date.now();
      return origPause.apply(this, arguments);
    }
    // Keep YouTube's own idea of the state (its play/pause button) in sync.
    setTimeout(function () {
      try { var mp = moviePlayer(); if (mp && mp.playVideo) mp.playVideo(); } catch (e) {}
    }, 0);
  };

  window.__adfree = {
    play: function () { userPaused = false; wantPlay = true; var v = video(); if (v) v.play(); },
    pause: function () {
      userPaused = true;
      wantPlay = false;
      var v = video();
      appPause = true;
      try { if (v) v.pause(); } finally { appPause = false; }
    },
    seek: function (t) { var v = video(); if (v) v.currentTime = t; },
    rate: function (r) { var v = video(); if (v) v.playbackRate = r; window.__adfreeRate = r; },
    quality: function (q) { wantQuality = q; appliedQuality = ''; },
  };

  function tick() {
    addCss();
    var v = video();
    if (!v) return;
    if (!v.__adfreeResume) {
      // The WebView suspends media itself when the app goes to the
      // background; start it again unless someone actually paused it.
      v.__adfreeResume = true;
      // Two players (main + Shorts) take audio focus from each other, and the
      // WebView resumes a player natively when it gets focus back. Keep a
      // player that was paused on purpose paused.
      v.addEventListener('play', function () {
        var el = this;
        if (userPaused && Date.now() - lastInput > 1500) {
          appPause = true;
          try { origPause.call(el); } finally { appPause = false; }
        }
      });
      v.addEventListener('pause', function () {
        var el = this;
        if (el.ended || userPaused || Date.now() - allowedPauseAt < 1000) return;
        // Resume right away: timers in a background page are slowed to ~1s,
        // which was an audible gap on screen lock. Promise callbacks are not.
        Promise.resolve().then(function () {
          if (el.paused && !el.ended && !userPaused) el.play().catch(function () {});
        });
      });
    }
    var ad = !!document.querySelector('.ad-showing,.ad-interrupting');
    if (ad) {
      // Anything that slipped through: mute it and jump to its end.
      if (!v.muted) { v.muted = true; v.__adfreeMuted = true; }
      if (isFinite(v.duration) && v.duration > 0) v.currentTime = v.duration;
      document.querySelectorAll('.ytp-ad-skip-button,.ytp-ad-skip-button-modern,.ytp-skip-ad-button,.ytp-ad-skip-button-slot button')
        .forEach(function (b) { b.click(); });
    } else if (v.__adfreeMuted) {
      v.muted = false;
      v.__adfreeMuted = false;
    }
    // The mobile site starts videos muted (autoplay rules); this app can play
    // with sound, so turn it back on.
    var mp0 = moviePlayer();
    if (!ad && !userMuted) {
      try { if (mp0 && mp0.isMuted && mp0.isMuted()) { mp0.unMute(); mp0.setVolume(100); } } catch (e) {}
      if (v.muted) v.muted = false;
    }
    if (wantPlay && !userPaused && v.paused && !v.ended && v.readyState >= 2) v.play().catch(function () {});
    if (!v.paused) wantPlay = false;
    if (window.__adfreeRate && v.playbackRate !== window.__adfreeRate) v.playbackRate = window.__adfreeRate;

    var mp = moviePlayer();
    var levels = [];
    try { levels = (mp && mp.getAvailableQualityLevels && mp.getAvailableQualityLevels()) || []; } catch (e) {}
    var id = currentId();
    if (mp && levels.length && appliedQuality !== id + wantQuality) {
      appliedQuality = id + wantQuality;
      try {
        if (wantQuality === 'auto') mp.setPlaybackQualityRange('auto');
        else mp.setPlaybackQualityRange(wantQuality, wantQuality);
      } catch (e) {}
    }

    var state = JSON.stringify({
      v: id,
      t: Math.floor((v.currentTime || 0) * 2) / 2,
      d: isFinite(v.duration) ? Math.floor(v.duration) : 0,
      p: !v.paused,
      e: v.ended,
      b: !v.paused && v.readyState < 3,
      ad: ad,
      q: levels,
    });
    if (state !== last && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      last = state;
      window.flutter_inappwebview.callHandler('state', state);
    }
  }
  setInterval(tick, 400);
})();
''';
