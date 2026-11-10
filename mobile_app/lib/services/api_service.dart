import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/video_model.dart';
import 'google_oauth.dart';
import 'innertube.dart';
import 'yt_parser.dart';

/// All data comes straight from youtube.com: no separate server is needed.
///
/// * Feeds, search, watch page, comments, channels -> InnerTube (signed in when
///   the user has logged in with Google).
/// * Playback -> YouTube's own web player with the ads stripped out
///   (see web_player.dart).
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final InnerTube _it = InnerTube.instance;

  bool get isSignedIn => _it.isSignedIn;

  // Logged-out YouTube has no personalised home, so categories map to
  // YouTube's own topic destination pages.
  static const Map<String, String> categoryPages = {
    'Music': 'UC-9-kyTW8ZkZNDHQJ6FgpwQ',
    'Gaming': 'UCOpNcN46UbXVtpKMrmU4Abg',
    'News': 'UCYfdidRxbB8Qhf0Nx7ioOYw',
    'Sports': 'UCEgdi0XIXXZ-qJOFPf4JSKw',
    'Live': 'UC4R8DWoMoI7CAwX8_LjQHig',
    'Learning': 'UCtFRv9O2AHqOZjjynzrv-xg',
  };

  static String extractVideoId(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return '';

    // Direct 11-char ID
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) {
      return clean;
    }

    final patterns = [
      RegExp(r'(?:https?:\/\/)?(?:www\.|m\.|music\.)?youtube\.com\/watch\?.*v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'(?:https?:\/\/)?youtu\.be\/([a-zA-Z0-9_-]{11})'),
      RegExp(r'(?:https?:\/\/)?(?:www\.|m\.)?youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})'),
      RegExp(r'(?:https?:\/\/)?(?:www\.|m\.)?youtube\.com\/embed\/([a-zA-Z0-9_-]{11})'),
      RegExp(r'(?:https?:\/\/)?(?:www\.|m\.)?youtube\.com\/v\/([a-zA-Z0-9_-]{11})'),
      RegExp(r'(?:https?:\/\/)?(?:www\.|m\.)?youtube\.com\/live\/([a-zA-Z0-9_-]{11})'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(clean);
      if (m != null && m.groupCount >= 1) {
        return m.group(1)!;
      }
    }
    return '';
  }

  // ------------------------------------------------------------------ feeds

  /// The real YouTube home feed. Personalised when signed in.
  Future<FeedPage> getHome({String? continuation}) async {
    try {
      final json = continuation == null
          ? await _it.browse(browseId: 'FEwhat_to_watch')
          : await _it.browse(continuation: continuation);
      return YtParser.feed(json);
    } catch (e) {
      debugPrint('Error getting home: $e');
      return FeedPage.empty();
    }
  }

  /// A home chip's feed ("Music", "Podcasts", ... from the signed-in home page).
  Future<FeedPage> getChipFeed(String token) => getHome(continuation: token);

  /// Topic feed used when signed out (or as a fallback).
  Future<FeedPage> getCategory(String category) async {
    final browseId = categoryPages[category];
    try {
      if (browseId != null) {
        final page = YtParser.feed(await _it.browse(browseId: browseId));
        if (page.videos.length >= 10) return page;
      }
      // Thin destination page or unknown category: fall back to search.
      return await search(category == 'All' ? 'popular videos today' : '$category popular');
    } catch (e) {
      debugPrint('Error getting category $category: $e');
      return FeedPage.empty();
    }
  }

  /// Signed-out "All": a mix of several topic pages, interleaved.
  Future<FeedPage> getExploreMix() async {
    final pages = await Future.wait(
      ['Music', 'Sports', 'Learning', 'News'].map(getCategory),
    );
    final mixed = <VideoItem>[];
    final seen = <String>{};
    final longest = pages.fold<int>(0, (m, p) => p.videos.length > m ? p.videos.length : m);
    for (var i = 0; i < longest && mixed.length < 60; i++) {
      for (final p in pages) {
        if (i < p.videos.length && !p.videos[i].isShort && seen.add(p.videos[i].id)) {
          mixed.add(p.videos[i]);
        }
      }
    }
    return FeedPage(videos: mixed);
  }

  Future<FeedPage> search(String query, {String? continuation}) async {
    try {
      final json = continuation == null
          ? await _it.search(query: query)
          : await _it.search(continuation: continuation);
      final page = YtParser.feed(json);
      return FeedPage(videos: page.videos, continuation: page.continuation, fromSearch: true);
    } catch (e) {
      debugPrint('Error searching: $e');
      return FeedPage.empty();
    }
  }

  Future<List<String>> getSuggestions(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      return await _it.suggestions(query);
    } catch (e) {
      debugPrint('Error getting suggestions: $e');
      return [];
    }
  }

  /// Shorts for the Shorts tab: reels from the home feed plus Shorts search results.
  Future<List<VideoItem>> getShorts({String seed = 'shorts'}) async {
    final results = await Future.wait([
      getHome(),
      search(seed),
    ]);
    final seen = <String>{};
    return [
      for (final page in results)
        for (final v in page.videos)
          if (v.isShort && seen.add(v.id)) v,
    ];
  }

  // ------------------------------------------------------------------ account feeds

  Future<FeedPage> getSubscriptionsFeed({String? continuation}) async {
    try {
      final json = continuation == null
          ? await _it.browse(browseId: 'FEsubscriptions')
          : await _it.browse(continuation: continuation);
      return YtParser.feed(json);
    } catch (e) {
      debugPrint('Error getting subscriptions feed: $e');
      return FeedPage.empty();
    }
  }

  Future<List<ChannelProfile>> getSubscribedChannels() async {
    try {
      return YtParser.channelList(await _it.browse(browseId: 'FEchannels'));
    } catch (e) {
      debugPrint('Error getting subscribed channels: $e');
      return [];
    }
  }

  /// Account lists: 'FEhistory', 'VLWL' (Watch later), 'VLLL' (Liked videos).
  Future<FeedPage> getAccountList(String browseId, {String? continuation}) async {
    try {
      final json = continuation == null
          ? await _it.browse(browseId: browseId)
          : await _it.browse(continuation: continuation);
      return YtParser.feed(json);
    } catch (e) {
      debugPrint('Error getting $browseId: $e');
      return FeedPage.empty();
    }
  }

  Future<AccountInfo?> getAccountInfo() async {
    try {
      final info = YtParser.account(await _it.accountMenu());
      if (info != null) return info;
    } catch (e) {
      debugPrint('Error getting account: $e');
    }
    // Browser (OAuth) sign-in: ask the official API for the user's channel.
    try {
      final token = await GoogleOAuth.accessToken();
      if (token == null) return null;
      final res = await http.get(
        Uri.parse('https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) {
        debugPrint('YouTube Data API channels: HTTP ${res.statusCode} ${res.body}');
        return null;
      }
      final items = (jsonDecode(res.body)['items'] as List?) ?? const [];
      if (items.isEmpty) return null;
      final snippet = items.first['snippet'] as Map<String, dynamic>;
      return AccountInfo(
        name: snippet['title'] as String? ?? '',
        handle: snippet['customUrl'] as String? ?? '',
        avatar: (snippet['thumbnails']?['default']?['url'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('Error getting account from Data API: $e');
      return null;
    }
  }

  Future<bool> setSubscribed(String channelId, bool subscribed) async {
    try {
      await _it.subscribe(channelId, subscribe: subscribed);
      return true;
    } catch (e) {
      debugPrint('Error changing subscription: $e');
      return false;
    }
  }

  Future<bool> setLiked(String videoId, bool liked) async {
    try {
      await _it.like(videoId, like: liked);
      return true;
    } catch (e) {
      debugPrint('Error changing like: $e');
      return false;
    }
  }

  // ------------------------------------------------------------------ watch

  Future<VideoDetails?> getVideoDetails(String videoIdOrUrl) async {
    final cleanId = extractVideoId(videoIdOrUrl);
    final id = cleanId.isNotEmpty ? cleanId : videoIdOrUrl.trim();
    if (id.isEmpty) return null;

    try {
      final info = YtParser.watchNext(await _it.next(videoId: id), id);

      return VideoDetails(
        id: id,
        title: info.title,
        description: info.description,
        channelName: info.channelName,
        channelId: info.channelId,
        channelAvatar: info.channelAvatar,
        duration: 0,
        viewCount: info.viewCount,
        likeCount: info.likeCount,
        uploadDate: '',
        thumbnail: info.thumbnail,
        primaryStreamUrl: '',
        videoStreams: const [],
        audioStreams: const [],
        relatedVideos: info.relatedVideos,
        comments: const [],
        viewText: info.viewText,
        publishedText: info.publishedText,
        likeText: info.likeText,
        subscriberText: info.subscriberText,
        commentCountText: info.commentCountText,
        commentsToken: info.commentsToken,
        relatedToken: info.relatedToken,
        isLive: info.isLive,
        isSubscribed: info.isSubscribed,
        isLiked: info.isLiked,
      );
    } catch (e) {
      debugPrint('Error getting video details: $e');
      return null;
    }
  }



  Future<CommentPage> getComments(String token) async {
    try {
      return YtParser.comments(await _it.next(continuation: token));
    } catch (e) {
      debugPrint('Error getting comments: $e');
      return CommentPage(comments: []);
    }
  }

  // ------------------------------------------------------------------ channels

  Future<ChannelProfile?> getChannelDetails(String channelIdOrHandle) async {
    try {
      var id = channelIdOrHandle.trim();
      if (!id.startsWith('UC')) {
        // Handle (@name) or URL -> channel id.
        final url = id.startsWith('http') ? id : 'https://www.youtube.com/${id.startsWith('@') ? id : '@$id'}';
        final resolved = YtParser.find(await _it.resolveUrl(url), 'browseId');
        if (resolved is String) id = resolved;
      }
      // "Videos" tab of the channel.
      final json = await _it.browse(browseId: id, params: 'EgZ2aWRlb3PyBgQKAjoA');
      return YtParser.channel(json, id);
    } catch (e) {
      debugPrint('Error getting channel details: $e');
      return null;
    }
  }
}

