import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_model.dart';

class SubscribedChannel {
  final String id;
  final String name;
  final String avatar;

  SubscribedChannel({
    required this.id,
    required this.name,
    required this.avatar,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
  };

  factory SubscribedChannel.fromJson(Map<String, dynamic> json) => SubscribedChannel(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    avatar: json['avatar'] ?? '',
  );
}

class StorageService {
  static const _keyQuality = 'settings_quality';
  static const _keySubscriptions = 'local_subscriptions';
  static const _keyHistory = 'watch_history';
  static const _keyLiked = 'liked_videos';
  static const _keyRecentSearches = 'recent_searches';
  static const _keyWatchLater = 'watch_later';

  // Quality Preference
  static Future<String> getPreferredQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyQuality) ?? 'Auto';
  }

  static Future<void> setPreferredQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyQuality, quality);
  }

  // Subscriptions
  static Future<List<SubscribedChannel>> getSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keySubscriptions) ?? [];
    return raw.map((item) {
      try {
        return SubscribedChannel.fromJson(json.decode(item));
      } catch (_) {
        return null;
      }
    }).whereType<SubscribedChannel>().toList();
  }

  static Future<bool> isSubscribed(String channelId) async {
    final subs = await getSubscriptions();
    return subs.any((s) => s.id == channelId);
  }

  static Future<void> toggleSubscription(SubscribedChannel channel) async {
    final prefs = await SharedPreferences.getInstance();
    var subs = await getSubscriptions();
    final index = subs.indexWhere((s) => s.id == channel.id);
    if (index >= 0) {
      subs.removeAt(index);
    } else {
      subs.insert(0, channel);
    }
    final encoded = subs.map((s) => json.encode(s.toJson())).toList();
    await prefs.setStringList(_keySubscriptions, encoded);
  }

  // Watch History
  static Future<List<VideoItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyHistory) ?? [];
    return raw.map((item) {
      try {
        return VideoItem.fromJson(json.decode(item));
      } catch (_) {
        return null;
      }
    }).whereType<VideoItem>().toList();
  }

  static Future<void> addToHistory(VideoItem video) async {
    final prefs = await SharedPreferences.getInstance();
    var history = await getHistory();
    history.removeWhere((v) => v.id == video.id);
    history.insert(0, video);
    if (history.length > 100) {
      history = history.sublist(0, 100);
    }
    final encoded = history.map((v) => json.encode(v.toJson())).toList();
    await prefs.setStringList(_keyHistory, encoded);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }

  // Liked Videos
  static Future<List<VideoItem>> getLikedVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyLiked) ?? [];
    return raw.map((item) {
      try {
        return VideoItem.fromJson(json.decode(item));
      } catch (_) {
        return null;
      }
    }).whereType<VideoItem>().toList();
  }

  static Future<bool> isLiked(String videoId) async {
    final liked = await getLikedVideos();
    return liked.any((v) => v.id == videoId);
  }

  static Future<void> toggleLike(VideoItem video) async {
    final prefs = await SharedPreferences.getInstance();
    var liked = await getLikedVideos();
    final index = liked.indexWhere((v) => v.id == video.id);
    if (index >= 0) {
      liked.removeAt(index);
    } else {
      liked.insert(0, video);
    }
    final encoded = liked.map((v) => json.encode(v.toJson())).toList();
    await prefs.setStringList(_keyLiked, encoded);
  }

  // Watch Later (local, used when not signed in)
  static Future<List<VideoItem>> getWatchLater() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyWatchLater) ?? [];
    return raw.map((item) {
      try {
        return VideoItem.fromJson(json.decode(item));
      } catch (_) {
        return null;
      }
    }).whereType<VideoItem>().toList();
  }

  /// Returns true if the video is now in Watch Later.
  static Future<bool> toggleWatchLater(VideoItem video) async {
    final prefs = await SharedPreferences.getInstance();
    var list = await getWatchLater();
    final index = list.indexWhere((v) => v.id == video.id);
    if (index >= 0) {
      list.removeAt(index);
    } else {
      list.insert(0, video);
    }
    final encoded = list.map((v) => json.encode(v.toJson())).toList();
    await prefs.setStringList(_keyWatchLater, encoded);
    return index < 0;
  }

  // Recent Searches
  static Future<List<String>> getRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyRecentSearches) ?? [];
  }

  static Future<void> addRecentSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    var searches = await getRecentSearches();
    searches.remove(trimmed);
    searches.insert(0, trimmed);
    if (searches.length > 20) {
      searches = searches.sublist(0, 20);
    }
    await prefs.setStringList(_keyRecentSearches, searches);
  }

  static Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRecentSearches);
  }
}
