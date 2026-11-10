import 'package:flutter/material.dart';
import '../models/video_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// Subscriptions + "You" tab data.
///
/// Signed in, everything comes from the YouTube account (subscriptions feed,
/// history, Watch later, Liked videos). Signed out, it uses the on-device lists.
class LibraryProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<VideoItem> _history = [];
  List<VideoItem> _likedVideos = [];
  List<VideoItem> _watchLater = [];
  List<SubscribedChannel> _subscriptions = [];
  List<VideoItem> _subscriptionVideos = [];
  String? _subscriptionsContinuation;
  bool _isLoadingSubscriptions = false;
  bool _isLoadingMoreSubscriptions = false;
  bool _isLoadingLibrary = false;

  List<VideoItem> get history => _history;
  List<VideoItem> get likedVideos => _likedVideos;
  List<VideoItem> get watchLater => _watchLater;
  List<SubscribedChannel> get subscriptions => _subscriptions;
  List<VideoItem> get subscriptionVideos => _subscriptionVideos;
  bool get isLoadingSubscriptions => _isLoadingSubscriptions;
  bool get isLoadingMoreSubscriptions => _isLoadingMoreSubscriptions;
  bool get isLoadingLibrary => _isLoadingLibrary;
  bool get isSignedIn => _apiService.isSignedIn;

  LibraryProvider() {
    loadAll();
  }

  Future<void> loadAll() async {
    await Future.wait([loadLibrary(), refreshSubscriptions()]);
  }

  Future<void> loadLibrary() async {
    if (!isSignedIn) {
      _history = await StorageService.getHistory();
      _likedVideos = await StorageService.getLikedVideos();
      _watchLater = await StorageService.getWatchLater();
      notifyListeners();
      return;
    }

    _isLoadingLibrary = true;
    notifyListeners();
    final pages = await Future.wait([
      _apiService.getAccountList('FEhistory'),
      _apiService.getAccountList('VLLL'),
      _apiService.getAccountList('VLWL'),
    ]);
    _history = pages[0].videos.where((v) => !v.isShort).toList();
    _likedVideos = pages[1].videos;
    // "Save" in the app is stored on the phone; show it alongside the account list.
    final localSaved = await StorageService.getWatchLater();
    final seen = <String>{};
    _watchLater = [...localSaved, ...pages[2].videos].where((v) => seen.add(v.id)).toList();
    _isLoadingLibrary = false;
    notifyListeners();
  }

  Future<void> refreshSubscriptions() async {
    _isLoadingSubscriptions = true;
    notifyListeners();

    if (isSignedIn) {
      final results = await Future.wait([
        _apiService.getSubscribedChannels(),
        _apiService.getSubscriptionsFeed(),
      ]);
      final channels = results[0] as List<ChannelProfile>;
      final feed = results[1] as FeedPage;
      _subscriptions = channels
          .map((c) => SubscribedChannel(id: c.id, name: c.title, avatar: c.avatar))
          .toList();
      _subscriptionVideos = feed.videos.where((v) => !v.isShort).toList();
      _subscriptionsContinuation = feed.continuation;
    } else {
      _subscriptions = await StorageService.getSubscriptions();
      _subscriptionVideos = await _localSubscriptionFeed();
      _subscriptionsContinuation = null;
    }

    _isLoadingSubscriptions = false;
    notifyListeners();
  }

  /// Signed out: newest uploads from up to 8 locally subscribed channels.
  Future<List<VideoItem>> _localSubscriptionFeed() async {
    if (_subscriptions.isEmpty) return [];
    final profiles = await Future.wait(
      _subscriptions.take(8).map((c) => _apiService.getChannelDetails(c.id)),
    );
    final perChannel = [
      for (final p in profiles)
        if (p != null) p.videos.where((v) => !v.isShort).take(5).toList(),
    ];
    // Interleave so the feed isn't one channel after another.
    final feed = <VideoItem>[];
    for (var i = 0; i < 5; i++) {
      for (final list in perChannel) {
        if (i < list.length) feed.add(list[i]);
      }
    }
    return feed;
  }

  Future<void> loadMoreSubscriptions() async {
    if (_isLoadingMoreSubscriptions || _subscriptionsContinuation == null) return;
    _isLoadingMoreSubscriptions = true;
    notifyListeners();
    try {
      final page = await _apiService.getSubscriptionsFeed(continuation: _subscriptionsContinuation);
      final seen = _subscriptionVideos.map((v) => v.id).toSet();
      _subscriptionVideos = [
        ..._subscriptionVideos,
        ...page.videos.where((v) => !v.isShort && seen.add(v.id)),
      ];
      _subscriptionsContinuation = page.continuation;
    } finally {
      _isLoadingMoreSubscriptions = false;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    _history = [];
    await StorageService.clearHistory();
    notifyListeners();
  }
}
