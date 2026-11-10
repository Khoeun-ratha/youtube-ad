import '../models/video_model.dart';

/// Turns raw InnerTube JSON into app models.
///
/// YouTube ships several generations of renderers at once (videoRenderer,
/// lockupViewModel, shortsLockupViewModel, ...), and nests them differently on
/// every page, so instead of hard-coding paths we walk the whole tree and pick
/// up every renderer we understand. Ad renderers are skipped entirely.
class YtParser {
  static const _adKeys = {
    'adSlotRenderer',
    'promotedSparklesWebRenderer',
    'promotedVideoRenderer',
    'compactPromotedVideoRenderer',
    'displayAdRenderer',
    'searchPyvRenderer',
    'inFeedAdLayoutRenderer',
    'statementBannerRenderer',
    'brandVideoShelfRenderer',
    'brandVideoSingletonRenderer',
    'bannerPromoRenderer',
    'mealbarPromoRenderer',
    'adsEngagementPanelContentRenderer',
    'playerLegacyDesktopWatchAdsRenderer',
  };

  static const _videoKeys = {
    'videoRenderer',
    'compactVideoRenderer',
    'gridVideoRenderer',
    'playlistVideoRenderer',
    'lockupViewModel',
    'reelItemRenderer',
    'shortsLockupViewModel',
  };

  // ---------------------------------------------------------------- helpers

  static String text(dynamic node) {
    if (node == null) return '';
    if (node is String) return node;
    if (node is Map) {
      if (node['simpleText'] is String) return node['simpleText'];
      if (node['content'] is String) return node['content'];
      if (node['runs'] is List) {
        return (node['runs'] as List).map((r) => r is Map ? (r['text'] ?? '') : '').join();
      }
    }
    return '';
  }

  /// Depth-first search for the first value stored under [key].
  static dynamic find(dynamic node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final v in node.values) {
        final r = find(v, key);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = find(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }

  static List<dynamic> findAll(dynamic node, String key, [List<dynamic>? out]) {
    out ??= [];
    if (node is Map) {
      node.forEach((k, v) {
        if (k == key) out!.add(v);
        findAll(v, key, out);
      });
    } else if (node is List) {
      for (final v in node) {
        findAll(v, key, out);
      }
    }
    return out;
  }

  static String bestImage(dynamic node) {
    if (node is! Map) return '';
    final list = node['thumbnails'] ?? node['sources'];
    if (list is! List || list.isEmpty) return '';
    Map? best;
    for (final t in list) {
      if (t is! Map || t['url'] is! String) continue;
      if (best == null || (t['width'] ?? 0) > (best['width'] ?? 0)) best = t;
    }
    var url = (best?['url'] ?? '') as String;
    if (url.startsWith('//')) url = 'https:$url';
    return url;
  }

  static int parseDuration(String s) {
    final parts = s.trim().split(':');
    if (parts.length < 2) return 0;
    var total = 0;
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      if (n == null) return 0;
      total = total * 60 + n;
    }
    return total;
  }

  /// "58,560,484 views" -> 58560484, "1.8B views" -> 1800000000, "552K" -> 552000.
  static int parseCount(String s) {
    final m = RegExp(r'([\d.,]+)\s*([KMB])?', caseSensitive: false).firstMatch(s);
    if (m == null) return 0;
    final suffix = (m.group(2) ?? '').toUpperCase();
    if (suffix.isEmpty) return int.tryParse(m.group(1)!.replaceAll(RegExp(r'[,.]'), '')) ?? 0;
    final n = double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
    const mult = {'K': 1e3, 'M': 1e6, 'B': 1e9};
    return (n * mult[suffix]!).round();
  }

  static String _withViews(String s) {
    if (s.isEmpty) return s;
    final lower = s.toLowerCase();
    if (lower.contains('view') || lower.contains('watching') || lower.contains('waiting')) return s;
    return '$s views';
  }

  static String? _browseId(dynamic node) {
    final ep = find(node, 'browseEndpoint');
    if (ep is Map && ep['browseId'] is String) return ep['browseId'];
    return null;
  }

  static String _ytThumb(String id) => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

  // ---------------------------------------------------------------- videos

  /// Every video/short in [root], in page order, de-duplicated, ads excluded.
  static List<VideoItem> videos(dynamic root) {
    final out = <VideoItem>[];
    final seen = <String>{};
    void walk(dynamic node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final k = entry.key;
          if (_adKeys.contains(k)) continue;
          if (_videoKeys.contains(k) && entry.value is Map) {
            final v = _parseVideo(k, entry.value as Map);
            if (v != null && seen.add(v.id)) out.add(v);
            continue;
          }
          walk(entry.value);
        }
      } else if (node is List) {
        for (final v in node) {
          walk(v);
        }
      }
    }

    walk(root);
    return out;
  }

  static VideoItem? _parseVideo(String kind, Map r) {
    switch (kind) {
      case 'lockupViewModel':
        return _parseLockup(r);
      case 'shortsLockupViewModel':
        return _parseShortsLockup(r);
      case 'reelItemRenderer':
        final id = r['videoId'];
        if (id is! String) return null;
        final views = text(r['viewCountText']);
        return VideoItem(
          id: id,
          title: text(r['headline']),
          channelName: '',
          channelId: '',
          channelAvatar: '',
          duration: 0,
          viewCount: parseCount(views),
          uploadDate: '',
          thumbnail: bestImage(r['thumbnail']).isNotEmpty ? bestImage(r['thumbnail']) : _ytThumb(id),
          viewText: views,
          isShort: true,
        );
      default:
        return _parseVideoRenderer(r);
    }
  }

  static VideoItem? _parseVideoRenderer(Map r) {
    final id = r['videoId'];
    if (id is! String) return null;
    final owner = r['ownerText'] ?? r['longBylineText'] ?? r['shortBylineText'];
    var lengthText = text(r['lengthText']);
    if (lengthText.isEmpty) {
      final overlay = find(r['thumbnailOverlays'], 'thumbnailOverlayTimeStatusRenderer');
      lengthText = text(overlay?['text']);
    }
    final badges = findAll(r['badges'], 'style').map((e) => e.toString());
    final isLive = badges.any((b) => b.contains('LIVE')) || lengthText.toUpperCase() == 'LIVE';
    final viewText = text(r['shortViewCountText']).isNotEmpty && isLive
        ? text(r['shortViewCountText'])
        : text(r['viewCountText']);
    final avatarNode = find(r['channelThumbnailSupportedRenderers'], 'thumbnail') ?? r['channelThumbnail'];
    final thumb = bestImage(r['thumbnail']);
    return VideoItem(
      id: id,
      title: text(r['title']),
      channelName: text(owner),
      channelId: _browseId(owner) ?? '',
      channelAvatar: bestImage(avatarNode),
      duration: parseDuration(lengthText),
      viewCount: parseCount(viewText),
      uploadDate: '',
      thumbnail: thumb.isNotEmpty ? thumb : _ytThumb(id),
      viewText: viewText,
      publishedText: text(r['publishedTimeText']),
      isLive: isLive,
    );
  }

  static VideoItem? _parseLockup(Map l) {
    if (l['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') return null;
    final id = l['contentId'];
    if (id is! String) return null;

    final meta = l['metadata']?['lockupMetadataViewModel'] ?? {};
    final thumbVm = l['contentImage']?['thumbnailViewModel'] ?? {};
    final thumb = bestImage(thumbVm['image']);

    var durationText = '';
    var isLive = false;
    for (final b in findAll(thumbVm['overlays'], 'thumbnailBadgeViewModel')) {
      if (b is! Map) continue;
      final style = '${b['badgeStyle'] ?? ''}';
      if (style.contains('LIVE')) isLive = true;
      final t = text(b['text']);
      if (durationText.isEmpty && t.contains(':')) durationText = t;
    }

    final avatarVm = find(meta['image'], 'avatarViewModel');
    final rows = (find(meta['metadata'], 'metadataRows') as List?) ?? const [];
    // Rows look like [[channel], [views, date]], [[channel, views]] or [[views, date]]
    // depending on the page, so classify each part by what it says.
    var channelName = '';
    var viewText = '';
    var published = '';
    for (final row in rows) {
      for (final p in (row is Map ? row['metadataParts'] as List? : null) ?? const []) {
        final t = text(p is Map ? p['text'] : null);
        if (t.isEmpty) continue;
        final lower = t.toLowerCase();
        if (viewText.isEmpty &&
            (lower.contains('view') || lower.contains('watching') || RegExp(r'^[\d.,]+[kmb]?$').hasMatch(lower))) {
          viewText = _withViews(t);
        } else if (published.isEmpty &&
            (lower.contains('ago') || lower.contains('streamed') || lower.contains('premier') || lower.contains('scheduled'))) {
          published = t;
        } else if (channelName.isEmpty) {
          channelName = t;
        }
      }
    }
    if (viewText.toLowerCase().contains('watching')) isLive = true;

    return VideoItem(
      id: id,
      title: text(meta['title']),
      channelName: channelName,
      channelId: _browseId(meta['image']) ?? _browseId(meta['metadata']) ?? '',
      channelAvatar: bestImage(avatarVm?['image']),
      duration: parseDuration(durationText),
      viewCount: parseCount(viewText),
      uploadDate: '',
      thumbnail: thumb.isNotEmpty ? thumb : _ytThumb(id),
      viewText: viewText,
      publishedText: published,
      isLive: isLive,
    );
  }

  static VideoItem? _parseShortsLockup(Map s) {
    final ep = find(s['onTap'], 'reelWatchEndpoint');
    String? id = ep is Map ? ep['videoId'] : null;
    id ??= (s['entityId'] as String?)?.replaceFirst('shorts-shelf-item-', '');
    if (id == null || id.isEmpty) return null;
    final overlay = s['overlayMetadata'] ?? {};
    final views = text(overlay['secondaryText']);
    final thumb = bestImage(s['thumbnail']) ;
    return VideoItem(
      id: id,
      title: text(overlay['primaryText']),
      channelName: '',
      channelId: '',
      channelAvatar: '',
      duration: 0,
      viewCount: parseCount(views),
      uploadDate: '',
      thumbnail: thumb.isNotEmpty ? thumb : 'https://i.ytimg.com/vi/$id/oardefault.jpg',
      viewText: views,
      isShort: true,
    );
  }

  // ---------------------------------------------------------------- feeds

  /// The continuation token that loads the next page of a feed/search.
  static String? continuation(dynamic root) {
    String? token;
    for (final c in findAll(root, 'continuationItemRenderer')) {
      // Comment reply buttons also use continuations; skip those.
      final t = find(c, 'continuationCommand')?['token'];
      if (t is String) token = t;
    }
    return token;
  }

  static List<FeedChip> chips(dynamic root) {
    final bar = find(root, 'feedFilterChipBarRenderer') ?? find(root, 'chipBarViewModel');
    if (bar == null) return [];
    final out = <FeedChip>[];
    for (final key in ['chipCloudChipRenderer', 'chipViewModel']) {
      for (final c in findAll(bar, key)) {
        if (c is! Map) continue;
        final title = text(c['text']);
        if (title.isEmpty) continue;
        final token = find(c, 'continuationCommand')?['token'];
        out.add(FeedChip(
          title: title,
          token: token is String ? token : null,
          selected: c['isSelected'] == true || c['selected'] == true,
        ));
      }
    }
    return out;
  }

  static FeedPage feed(dynamic root) => FeedPage(
        videos: videos(root),
        continuation: continuation(root),
        chips: chips(root),
      );

  // ---------------------------------------------------------------- watch page

  /// Parses the `next` response: metadata, owner, account state, related videos.
  static VideoDetails watchNext(Map<String, dynamic> json, String videoId) {
    final primary = find(json, 'videoPrimaryInfoRenderer') ?? {};
    final secondary = find(json, 'videoSecondaryInfoRenderer') ?? {};
    final owner = find(secondary, 'videoOwnerRenderer') ?? {};

    final viewCountRenderer = find(primary, 'videoViewCountRenderer') ?? {};
    final viewText = text(viewCountRenderer['viewCount']);
    final isLive = viewCountRenderer['isLive'] == true || viewText.contains('watching');

    final likeVm = find(primary, 'likeButtonViewModel');
    final likeTitle = find(likeVm, 'buttonViewModel')?['title'];
    final likeStatus = find(json, 'likeStatusEntity')?['likeStatus'];

    var subscribed = find(secondary, 'subscribeButtonRenderer')?['subscribed'] == true;
    final subEntity = find(json['frameworkUpdates'], 'subscriptionStateEntity');
    if (subEntity is Map && subEntity['subscribed'] is bool) subscribed = subEntity['subscribed'];

    var description = text(secondary['attributedDescription']);
    if (description.isEmpty) description = text(secondary['description']);

    String? commentsToken;
    String commentCount = '';
    for (final section in findAll(json['contents'], 'itemSectionRenderer')) {
      if (section is Map && section['sectionIdentifier'] == 'comment-item-section') {
        commentsToken = find(section, 'continuationCommand')?['token'];
      }
    }
    for (final panel in findAll(json['engagementPanels'], 'engagementPanelSectionListRenderer')) {
      if (panel is Map && panel['panelIdentifier'] == 'engagement-panel-comments-section') {
        commentCount = text(find(panel['header'], 'contextualInfo'));
      }
    }

    final secondaryResults = find(json, 'secondaryResults');
    final related = videos(secondaryResults).where((v) => v.id != videoId).toList();
    final channelName = text(owner['title']);

    return VideoDetails(
      id: videoId,
      title: text(primary['title']),
      description: description,
      channelName: channelName,
      channelId: _browseId(owner['title']) ?? _browseId(owner) ?? '',
      channelAvatar: bestImage(owner['thumbnail']),
      duration: 0,
      viewCount: parseCount(viewText),
      likeCount: parseCount(likeTitle is String ? likeTitle : ''),
      uploadDate: '',
      thumbnail: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      primaryStreamUrl: '',
      videoStreams: const [],
      audioStreams: const [],
      relatedVideos: related,
      comments: const [],
      viewText: viewText.isNotEmpty ? viewText : text(viewCountRenderer['shortViewCount']),
      publishedText: text(primary['relativeDateText']).isNotEmpty
          ? text(primary['relativeDateText'])
          : text(primary['dateText']),
      likeText: likeTitle is String ? likeTitle : '',
      subscriberText: text(owner['subscriberCountText']),
      commentCountText: commentCount,
      commentsToken: commentsToken,
      relatedToken: continuation(secondaryResults),
      isLive: isLive,
      isSubscribed: subscribed,
      isLiked: likeStatus == 'LIKE',
    );
  }

  // ---------------------------------------------------------------- comments

  static CommentPage comments(Map<String, dynamic> json) {
    final payloads = <String, Map>{};
    for (final m in findAll(json['frameworkUpdates'], 'commentEntityPayload')) {
      if (m is Map && m['properties'] is Map) {
        payloads[m['properties']['commentId'] ?? ''] = m;
      }
    }

    final out = <CommentItem>[];
    String? next;
    final actions = [
      ...((json['onResponseReceivedEndpoints'] as List?) ?? const []),
      ...((json['onResponseReceivedActions'] as List?) ?? const []),
    ];
    for (final action in actions) {
      final items = find(action, 'continuationItems');
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        if (item['continuationItemRenderer'] != null) {
          final t = find(item['continuationItemRenderer'], 'continuationCommand')?['token'];
          if (t is String) next = t;
          continue;
        }
        final thread = item['commentThreadRenderer'];
        if (thread is! Map) continue;
        // commentThreadRenderer.commentViewModel.commentViewModel.commentId
        var vm = find(thread, 'commentViewModel');
        if (vm is Map && vm['commentViewModel'] is Map) vm = vm['commentViewModel'];
        final id = vm is Map ? vm['commentId'] : null;
        final p = payloads[id];
        if (p == null) continue;
        final props = p['properties'] as Map;
        final author = (p['author'] ?? {}) as Map;
        final toolbar = (p['toolbar'] ?? {}) as Map;
        final likes = '${toolbar['likeCountNotliked'] ?? ''}'.trim();
        out.add(CommentItem(
          id: '${props['commentId']}',
          author: '${author['displayName'] ?? ''}',
          authorThumbnail: '${author['avatarThumbnailUrl'] ?? ''}',
          text: text(props['content']),
          likeCount: parseCount(likes),
          timestamp: 0,
          likeText: likes,
          publishedText: '${props['publishedTime'] ?? ''}',
          replyCount: '${toolbar['replyCount'] ?? ''}',
        ));
      }
    }
    return CommentPage(comments: out, continuation: next);
  }

  // ---------------------------------------------------------------- channel

  static ChannelProfile channel(Map<String, dynamic> json, String channelId) {
    final header = find(json['header'], 'pageHeaderViewModel');
    final meta = find(json['metadata'], 'channelMetadataRenderer') ?? {};

    var title = text(meta['title']);
    var avatar = bestImage(meta['avatar']);
    var banner = '';
    var handle = '';
    var subs = '';
    var videoCount = '';

    if (header is Map) {
      title = text(find(header['title'], 'text')).isNotEmpty ? text(find(header['title'], 'text')) : title;
      final av = find(header['image'], 'avatarViewModel');
      if (av is Map && bestImage(av['image']).isNotEmpty) avatar = bestImage(av['image']);
      banner = bestImage(find(header['banner'], 'image'));
      final rows = (find(header['metadata'], 'metadataRows') as List?) ?? const [];
      final parts = <String>[];
      for (final r in rows) {
        for (final p in (r is Map ? r['metadataParts'] as List? : null) ?? const []) {
          final t = text(p is Map ? p['text'] : null);
          if (t.isNotEmpty) parts.add(t);
        }
      }
      for (final p in parts) {
        final lower = p.toLowerCase();
        if (p.startsWith('@')) {
          handle = p;
        } else if (lower.contains('subscriber')) {
          subs = p;
        } else if (lower.contains('video')) {
          videoCount = p;
        }
      }
    } else {
      final c4 = find(json['header'], 'c4TabbedHeaderRenderer') ?? {};
      if (title.isEmpty) title = text(c4['title']);
      banner = bestImage(c4['banner']);
      subs = text(c4['subscriberCountText']);
      handle = text(c4['channelHandleText']);
    }

    var subscribed = false;
    final subEntity = find(json['frameworkUpdates'], 'subscriptionStateEntity');
    if (subEntity is Map && subEntity['subscribed'] is bool) subscribed = subEntity['subscribed'];

    final channelVideos = videos(json['contents'])
        .map((v) => VideoItem(
              id: v.id,
              title: v.title,
              channelName: v.channelName.isNotEmpty ? v.channelName : title,
              channelId: v.channelId.isNotEmpty ? v.channelId : channelId,
              channelAvatar: v.channelAvatar.isNotEmpty ? v.channelAvatar : avatar,
              duration: v.duration,
              viewCount: v.viewCount,
              uploadDate: v.uploadDate,
              thumbnail: v.thumbnail,
              viewText: v.viewText,
              publishedText: v.publishedText,
              isShort: v.isShort,
              isLive: v.isLive,
            ))
        .toList();

    return ChannelProfile(
      id: meta['externalId'] is String ? meta['externalId'] : channelId,
      title: title,
      description: '${meta['description'] ?? ''}',
      subscriberCount: parseCount(subs),
      avatar: avatar,
      banner: banner,
      videos: channelVideos,
      handle: handle,
      subscriberText: subs,
      videoCountText: videoCount,
      isSubscribed: subscribed,
    );
  }

  /// Channels listed on the "All subscriptions" page (FEchannels).
  static List<ChannelProfile> channelList(dynamic root) {
    final out = <ChannelProfile>[];
    final seen = <String>{};
    for (final c in findAll(root, 'channelRenderer')) {
      if (c is! Map || c['channelId'] is! String) continue;
      if (!seen.add(c['channelId'])) continue;
      out.add(ChannelProfile(
        id: c['channelId'],
        title: text(c['title']),
        description: text(c['descriptionSnippet']),
        subscriberCount: 0,
        avatar: bestImage(c['thumbnail']),
        banner: '',
        videos: const [],
        subscriberText: text(c['videoCountText']),
        isSubscribed: true,
      ));
    }
    return out;
  }

  static AccountInfo? account(Map<String, dynamic> json) {
    final header = find(json, 'activeAccountHeaderRenderer');
    if (header is! Map) return null;
    return AccountInfo(
      name: text(header['accountName']),
      handle: text(header['channelHandle']),
      avatar: bestImage(header['accountPhoto']),
    );
  }
}
