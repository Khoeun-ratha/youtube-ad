import 'package:flutter/material.dart';
import '../models/video_model.dart';
import '../services/api_service.dart';

class FeedProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  static const List<String> signedOutCategories = [
    'All',
    'Music',
    'Gaming',
    'News',
    'Sports',
    'Live',
    'Learning',
  ];

  String _selectedCategory = 'All';
  List<FeedChip> _homeChips = [];
  List<VideoItem> _videos = [];
  List<VideoItem> _shorts = [];
  String? _continuation;
  bool _continuationIsSearch = false;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;

  String get selectedCategory => _selectedCategory;
  List<VideoItem> get videos => _videos;
  List<VideoItem> get shorts => _shorts;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _continuation != null;
  String? get errorMessage => _errorMessage;

  /// Signed in: YouTube's own chips for your home feed. Signed out: topic pages.
  List<String> get categories {
    if (_apiService.isSignedIn && _homeChips.isNotEmpty) {
      return _homeChips.map((c) => c.title).toList();
    }
    return signedOutCategories;
  }

  FeedProvider() {
    loadFeed();
  }

  Future<void> changeCategory(String category) async {
    if (_selectedCategory == category && _videos.isNotEmpty) return;
    _selectedCategory = category;
    await loadFeed();
  }

  bool _isAllChip(String title) => title == 'All' || title == categories.first;

  Future<FeedPage> _fetch() async {
    if (_apiService.isSignedIn) {
      if (_isAllChip(_selectedCategory) || _homeChips.isEmpty) {
        final page = await _apiService.getHome();
        if (page.chips.isNotEmpty) _homeChips = page.chips;
        if (page.videos.isNotEmpty) return page;
      } else {
        final chip = _homeChips.where((c) => c.title == _selectedCategory).firstOrNull;
        if (chip?.token != null) return _apiService.getChipFeed(chip!.token!);
      }
    }
    // Signed out (or an empty personalised feed, e.g. watch history paused).
    if (_isAllChip(_selectedCategory)) return _apiService.getExploreMix();
    return _apiService.getCategory(_selectedCategory);
  }

  void _setPage(FeedPage page, {bool append = false}) {
    final seen = append ? {..._videos.map((v) => v.id), ..._shorts.map((v) => v.id)} : <String>{};
    final newVideos = page.videos.where((v) => seen.add(v.id));
    final regular = newVideos.where((v) => !v.isShort).toList();
    final shorts = page.videos.where((v) => v.isShort).toList();
    if (append) {
      _videos = [..._videos, ...regular];
      _shorts = [..._shorts, ...shorts.where((s) => !_shorts.any((e) => e.id == s.id))];
    } else {
      _videos = regular;
      _shorts = shorts;
    }
    _continuation = page.continuation;
    _continuationIsSearch = page.fromSearch;
  }

  Future<void> loadFeed() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _setPage(await _fetch());
      if (_videos.isEmpty) {
        _errorMessage = 'Couldn\'t load videos. Check your internet connection.';
      }
    } catch (e) {
      _errorMessage = 'Failed to load videos: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Infinite scroll: fetch the next page of the current feed.
  Future<void> loadMore() async {
    if (_isLoadingMore || _continuation == null) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = _continuationIsSearch
          ? await _apiService.search('', continuation: _continuation)
          : await _apiService.getHome(continuation: _continuation);
      _setPage(page, append: true);
    } catch (e) {
      debugPrint('Error loading more videos: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Called after signing in/out so the feed switches to/from the account.
  Future<void> reset() async {
    _homeChips = [];
    _selectedCategory = 'All';
    await loadFeed();
  }

  Future<void> refresh() async {
    await loadFeed();
  }
}
