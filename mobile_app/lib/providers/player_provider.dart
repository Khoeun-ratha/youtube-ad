import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/video_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/web_player.dart';

/// One player for the whole app, like the YouTube app: a video keeps playing
/// in the mini-player while you browse, and expands back to full screen.
class PlayerProvider extends ChangeNotifier {
  static const MethodChannel _wakeLockChannel = MethodChannel('com.adfree.youtube/wakelock');
  final ApiService _apiService = ApiService();

  /// YouTube's own web player (with ads removed) does the actual playback.
  final WebPlayer web = WebPlayer();

  VideoItem? _currentVideo;
  VideoDetails? _videoDetails;
  int _loadToken = 0;

  bool _isExpanded = false;
  bool _isFullscreen = false;
  bool _isLoading = false;
  bool _isLiked = false;
  bool _isSubscribed = false;
  bool _isAudioOnly = false;
  bool _autoplay = true;
  String _selectedQuality = 'Auto';
  String? _errorMessage;

  List<CommentItem> _comments = [];
  String? _commentsToken;
  bool _isLoadingComments = false;

  VideoItem? get currentVideo => _currentVideo;
  VideoDetails? get videoDetails => _videoDetails;
  bool get hasVideo => _currentVideo != null;
  bool get isExpanded => _isExpanded;
  bool get isFullscreen => _isFullscreen;

  /// Loading until the video actually starts playing.
  bool get isLoading => _isLoading || (hasVideo && !web.hasStarted && _errorMessage == null);
  bool get isPlaying => web.isPlaying;
  bool get isLiked => _isLiked;
  bool get isSubscribed => _isSubscribed;
  bool get isAudioOnly => _isAudioOnly;
  bool get autoplay => _autoplay;
  String get selectedQuality => _selectedQuality;
  String? get errorMessage => _errorMessage;
  Duration get currentPosition => web.position;
  Duration get totalDuration => web.duration;

  List<CommentItem> get comments => _comments;
  bool get isLoadingComments => _isLoadingComments;
  bool get hasMoreComments => _commentsToken != null;

  /// Distinct qualities offered for the current video, best first.
  List<String> get availableQualities => web.qualities;

  StreamSubscription<void>? _endedSub;
  bool _wasPlaying = false;
  bool _wasStarted = false;

  PlayerProvider() {
    web.addListener(_onWebChanged);
    web.onNavigated = _onWebNavigated;
    _endedSub = web.onEnded.listen((_) => _onCompleted());
  }

  /// Only rebuild listeners when something they show changes; position ticks
  /// are read straight from [web] by the widgets that need them.
  void _onWebChanged() {
    if (web.isPlaying == _wasPlaying && web.hasStarted == _wasStarted) return;
    _wasPlaying = web.isPlaying;
    _wasStarted = web.hasStarted;
    // The video plays even when its details failed to load.
    if (web.hasStarted) _errorMessage = null;
    _wasPlaying ? _acquireWakeLock() : _releaseWakeLock();
    notifyListeners();
  }

  /// The player page moved to another video on its own; show that one.
  void _onWebNavigated(String id) {
    if (id == _currentVideo?.id) return;
    playVideo(
      VideoItem(
        id: id,
        title: '',
        channelName: '',
        channelId: '',
        channelAvatar: '',
        duration: 0,
        viewCount: 0,
        uploadDate: '',
        thumbnail: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      ),
      expand: false,
      alreadyLoaded: true,
    );
  }

  Future<void> _acquireWakeLock() async {
    try {
      await _wakeLockChannel.invokeMethod('acquire');
    } catch (_) {}
  }

  Future<void> _releaseWakeLock() async {
    try {
      await _wakeLockChannel.invokeMethod('release');
    } catch (_) {}
  }

  // ---------------------------------------------------------------- panel

  void expand() {
    if (_isExpanded) return;
    _isExpanded = true;
    _keepPlaying();
    notifyListeners();
  }

  /// Fullscreen landscape playback, like rotating the phone in YouTube.
  void toggleFullscreen() {
    _isFullscreen = !_isFullscreen;
    if (_isFullscreen) {
      _isExpanded = true;
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _keepPlaying();
    notifyListeners();
  }

  void minimize() {
    if (_isFullscreen) toggleFullscreen();
    if (!_isExpanded) return;
    _isExpanded = false;
    _keepPlaying();
    notifyListeners();
  }

  /// Moving the player between the watch page and the mini-player must not
  /// stop the video; resume it if the page paused it.
  void _keepPlaying() {
    if (!web.isPlaying) return;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!web.isPlaying && web.hasStarted && hasVideo) web.play();
    });
  }

  /// Close the mini-player and stop playback.
  Future<void> close() async {
    _loadToken++;
    if (_isFullscreen) toggleFullscreen();
    await web.stop();
    _currentVideo = null;
    _videoDetails = null;
    _isExpanded = false;
    _errorMessage = null;
    _comments = [];
    _commentsToken = null;
    _releaseWakeLock();
    notifyListeners();
  }

  // ---------------------------------------------------------------- playback

  Future<void> playVideo(VideoItem video, {bool expand = true, bool alreadyLoaded = false}) async {
    if (expand) _isExpanded = true;
    if (_currentVideo?.id == video.id && _errorMessage == null) {
      notifyListeners();
      return;
    }

    final token = ++_loadToken;
    _currentVideo = video;
    _videoDetails = null;
    _isLoading = true;
    _errorMessage = null;
    _comments = [];
    _commentsToken = null;
    _selectedQuality = await StorageService.getPreferredQuality();
    // Start the player straight away; the details load alongside it.
    if (!alreadyLoaded) await web.load(video.id, quality: _selectedQuality);
    notifyListeners();

    await StorageService.addToHistory(video);
    _isLiked = await StorageService.isLiked(video.id);
    _isSubscribed = await StorageService.isSubscribed(video.channelId);

    try {
      final details = await _apiService.getVideoDetails(video.id);
      if (token != _loadToken) return;
      if (details == null) {
        // Only an error if the video itself isn't playing either.
        if (!web.hasStarted) _errorMessage = 'Could not load this video. Check your connection.';
        return;
      }
      _videoDetails = details;
      if (_apiService.isSignedIn) {
        _isLiked = details.isLiked;
        _isSubscribed = details.isSubscribed;
      }
      // Fill in what the feed card didn't know (avatar, channel id, ...).
      _currentVideo = _merge(video, details);
      _commentsToken = details.commentsToken;
      notifyListeners();
      loadMoreComments();
    } catch (e) {
      if (token == _loadToken && !web.hasStarted) _errorMessage = 'Failed to load video: $e';
    } finally {
      if (token == _loadToken) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  VideoItem _merge(VideoItem v, VideoDetails d) => VideoItem(
        id: v.id,
        title: d.title.isNotEmpty ? d.title : v.title,
        channelName: d.channelName.isNotEmpty ? d.channelName : v.channelName,
        channelId: d.channelId.isNotEmpty ? d.channelId : v.channelId,
        channelAvatar: d.channelAvatar.isNotEmpty ? d.channelAvatar : v.channelAvatar,
        duration: v.duration > 0 ? v.duration : d.duration,
        viewCount: d.viewCount > 0 ? d.viewCount : v.viewCount,
        uploadDate: v.uploadDate,
        thumbnail: v.thumbnail,
        viewText: d.viewText.isNotEmpty ? d.viewText : v.viewText,
        publishedText: d.publishedText.isNotEmpty ? d.publishedText : v.publishedText,
        isShort: v.isShort,
        isLive: d.isLive,
      );

  Future<void> retry() async {
    final v = _currentVideo;
    if (v == null) return;
    _currentVideo = null;
    await playVideo(v);
  }

  void _onCompleted() {
    if (!_autoplay) return;
    final next = _videoDetails?.relatedVideos.where((v) => !v.isShort).firstOrNull;
    // Autoplay keeps the panel in whatever state it is (mini or full).
    if (next != null) playVideo(next, expand: false);
  }

  void toggleAutoplay() {
    _autoplay = !_autoplay;
    notifyListeners();
  }

  Future<void> toggleAudioOnly() async {
    _isAudioOnly = !_isAudioOnly;
    notifyListeners();
    await web.setAudioOnly(_isAudioOnly);
  }

  Future<void> switchQuality(String quality) async {
    _selectedQuality = quality;
    notifyListeners();
    await web.setQuality(quality);
  }

  Future<void> togglePlayPause() => web.playOrPause();

  Future<void> pause() => web.pause();

  Future<void> seekTo(Duration position) => web.seek(position);

  Future<void> setSpeed(double speed) async {
    await web.setRate(speed);
    notifyListeners();
  }

  double get speed => web.rate;

  // ---------------------------------------------------------------- comments

  Future<void> loadMoreComments() async {
    final token = _commentsToken;
    if (token == null || _isLoadingComments) return;
    final videoId = _currentVideo?.id;
    _isLoadingComments = true;
    notifyListeners();
    final page = await _apiService.getComments(token);
    _isLoadingComments = false;
    if (videoId != _currentVideo?.id) return;
    _comments = [..._comments, ...page.comments];
    _commentsToken = page.continuation;
    notifyListeners();
  }

  // ---------------------------------------------------------------- account actions

  Future<void> toggleLike() async {
    final video = _currentVideo;
    if (video == null) return;
    _isLiked = !_isLiked;
    notifyListeners();
    if (_apiService.isSignedIn) {
      final ok = await _apiService.setLiked(video.id, _isLiked);
      if (!ok) {
        _isLiked = !_isLiked;
        notifyListeners();
      }
    } else {
      await StorageService.toggleLike(video);
    }
  }

  Future<void> toggleSubscribe() async {
    final video = _currentVideo;
    if (video == null || video.channelId.isEmpty) return;
    _isSubscribed = !_isSubscribed;
    notifyListeners();
    if (_apiService.isSignedIn) {
      final ok = await _apiService.setSubscribed(video.channelId, _isSubscribed);
      if (!ok) {
        _isSubscribed = !_isSubscribed;
        notifyListeners();
      }
    } else {
      await StorageService.toggleSubscription(SubscribedChannel(
        id: video.channelId,
        name: video.channelName,
        avatar: video.channelAvatar,
      ));
    }
  }

  @override
  void dispose() {
    _endedSub?.cancel();
    web.removeListener(_onWebChanged);
    _releaseWakeLock();
    web.dispose();
    super.dispose();
  }
}
