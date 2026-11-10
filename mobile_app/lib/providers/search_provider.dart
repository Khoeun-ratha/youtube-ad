import 'dart:async';
import 'package:flutter/material.dart';
import '../models/video_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class SearchProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  String _query = '';
  List<String> _suggestions = [];
  List<VideoItem> _searchResults = [];
  String? _continuation;
  bool _isLoadingMore = false;
  List<String> _recentSearches = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounceTimer;

  String get query => _query;
  List<String> get suggestions => _suggestions;
  List<VideoItem> get searchResults => _searchResults;
  List<String> get recentSearches => _recentSearches;
  bool get isLoading => _isLoading;
  bool get hasSearched => _hasSearched;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _continuation != null;

  SearchProvider() {
    loadRecentSearches();
  }

  Future<void> loadRecentSearches() async {
    _recentSearches = await StorageService.getRecentSearches();
    notifyListeners();
  }

  void onQueryChanged(String newQuery) {
    _query = newQuery;
    _debounceTimer?.cancel();

    if (newQuery.trim().isEmpty) {
      _suggestions = [];
      _hasSearched = false;
      notifyListeners();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final list = await _apiService.getSuggestions(newQuery);
      _suggestions = list;
      notifyListeners();
    });
  }

  Future<void> performSearch(String searchQuery) async {
    final cleanQuery = searchQuery.trim();
    if (cleanQuery.isEmpty) return;

    _query = cleanQuery;
    _isLoading = true;
    _hasSearched = true;
    _suggestions = [];
    notifyListeners();

    await StorageService.addRecentSearch(cleanQuery);
    await loadRecentSearches();

    try {
      final page = await _apiService.search(cleanQuery);
      _searchResults = page.videos;
      _continuation = page.continuation;
    } catch (e) {
      _searchResults = [];
      _continuation = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || _continuation == null) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _apiService.search(_query, continuation: _continuation);
      final seen = _searchResults.map((v) => v.id).toSet();
      _searchResults = [..._searchResults, ...page.videos.where((v) => seen.add(v.id))];
      _continuation = page.continuation;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> removeRecentSearch(String item) async {
    _recentSearches.remove(item);
    notifyListeners();
    final prefsSearches = await StorageService.getRecentSearches();
    prefsSearches.remove(item);
    // Persist
    await StorageService.clearRecentSearches();
    for (final s in prefsSearches.reversed) {
      await StorageService.addRecentSearch(s);
    }
  }

  Future<void> clearAllRecentSearches() async {
    _recentSearches = [];
    await StorageService.clearRecentSearches();
    notifyListeners();
  }

  void clearSearch() {
    _query = '';
    _suggestions = [];
    _searchResults = [];
    _continuation = null;
    _hasSearched = false;
    notifyListeners();
  }
}
