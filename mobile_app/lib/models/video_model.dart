class VideoItem {
  final String id;
  final String title;
  final String channelName;
  final String channelId;
  final String channelAvatar;
  final int duration;
  final int viewCount;
  final String uploadDate;
  final String thumbnail;
  // Display text exactly as YouTube shows it ("1.2M views", "3 days ago").
  final String viewText;
  final String publishedText;
  final bool isShort;
  final bool isLive;

  VideoItem({
    required this.id,
    required this.title,
    required this.channelName,
    required this.channelId,
    required this.channelAvatar,
    required this.duration,
    required this.viewCount,
    required this.uploadDate,
    required this.thumbnail,
    this.viewText = '',
    this.publishedText = '',
    this.isShort = false,
    this.isLive = false,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      channelName: json['channel_name'] ?? 'Unknown Creator',
      channelId: json['channel_id'] ?? '',
      channelAvatar: json['channel_avatar'] ?? '',
      duration: json['duration'] is int ? json['duration'] : 0,
      viewCount: json['view_count'] is int ? json['view_count'] : 0,
      uploadDate: json['upload_date'] ?? '',
      thumbnail: json['thumbnail'] ?? '',
      viewText: json['view_text'] ?? '',
      publishedText: json['published_text'] ?? '',
      isShort: json['is_short'] == true,
      isLive: json['is_live'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'channel_name': channelName,
      'channel_id': channelId,
      'channel_avatar': channelAvatar,
      'duration': duration,
      'view_count': viewCount,
      'upload_date': uploadDate,
      'thumbnail': thumbnail,
      'view_text': viewText,
      'published_text': publishedText,
      'is_short': isShort,
      'is_live': isLive,
    };
  }
}

class StreamFormat {
  final String formatId;
  final String quality;
  final String resolution;
  final String ext;
  final String url;
  final int filesize;
  final int height;
  // True when the stream already contains audio (no separate audio track needed).
  final bool isMuxed;

  StreamFormat({
    required this.formatId,
    required this.quality,
    required this.resolution,
    required this.ext,
    required this.url,
    required this.filesize,
    this.height = 0,
    this.isMuxed = false,
  });

  factory StreamFormat.fromJson(Map<String, dynamic> json) {
    return StreamFormat(
      formatId: json['format_id']?.toString() ?? '',
      quality: json['quality'] ?? 'Auto',
      resolution: json['resolution'] ?? '',
      ext: json['ext'] ?? 'mp4',
      url: json['url'] ?? '',
      filesize: json['filesize'] is int ? json['filesize'] : 0,
    );
  }
}

class AudioFormat {
  final String formatId;
  final String ext;
  final int abr;
  final String url;

  AudioFormat({
    required this.formatId,
    required this.ext,
    required this.abr,
    required this.url,
  });

  factory AudioFormat.fromJson(Map<String, dynamic> json) {
    return AudioFormat(
      formatId: json['format_id']?.toString() ?? '',
      ext: json['ext'] ?? 'm4a',
      abr: json['abr'] is int ? json['abr'] : 128,
      url: json['url'] ?? '',
    );
  }
}

class CommentItem {
  final String id;
  final String author;
  final String authorThumbnail;
  final String text;
  final int likeCount;
  final int timestamp;
  final String likeText;
  final String publishedText;
  final String replyCount;

  CommentItem({
    required this.id,
    required this.author,
    required this.authorThumbnail,
    required this.text,
    required this.likeCount,
    required this.timestamp,
    this.likeText = '',
    this.publishedText = '',
    this.replyCount = '',
  });

  factory CommentItem.fromJson(Map<String, dynamic> json) {
    return CommentItem(
      id: json['id'] ?? '',
      author: json['author'] ?? 'Anonymous',
      authorThumbnail: json['author_thumbnail'] ?? '',
      text: json['text'] ?? '',
      likeCount: json['like_count'] is int ? json['like_count'] : 0,
      timestamp: json['timestamp'] is int ? json['timestamp'] : 0,
    );
  }
}

class VideoDetails {
  final String id;
  final String title;
  final String description;
  final String channelName;
  final String channelId;
  final String channelAvatar;
  final int duration;
  final int viewCount;
  final int likeCount;
  final String uploadDate;
  final String thumbnail;
  final String primaryStreamUrl;
  final String? hlsManifestUrl;
  final List<StreamFormat> videoStreams;
  final List<AudioFormat> audioStreams;
  final List<VideoItem> relatedVideos;
  final List<CommentItem> comments;
  final String viewText;
  final String publishedText;
  final String likeText;
  final String subscriberText;
  final String commentCountText;
  final String? commentsToken;
  final String? relatedToken;
  final bool isLive;
  // Account state (only meaningful when signed in).
  final bool isSubscribed;
  final bool isLiked;

  VideoDetails({
    required this.id,
    required this.title,
    required this.description,
    required this.channelName,
    required this.channelId,
    required this.channelAvatar,
    required this.duration,
    required this.viewCount,
    required this.likeCount,
    required this.uploadDate,
    required this.thumbnail,
    required this.primaryStreamUrl,
    this.hlsManifestUrl,
    required this.videoStreams,
    required this.audioStreams,
    required this.relatedVideos,
    required this.comments,
    this.viewText = '',
    this.publishedText = '',
    this.likeText = '',
    this.subscriberText = '',
    this.commentCountText = '',
    this.commentsToken,
    this.relatedToken,
    this.isLive = false,
    this.isSubscribed = false,
    this.isLiked = false,
  });

  factory VideoDetails.fromJson(Map<String, dynamic> json) {
    var vStreams = <StreamFormat>[];
    if (json['video_streams'] is List) {
      vStreams = (json['video_streams'] as List)
          .map((v) => StreamFormat.fromJson(v))
          .toList();
    }

    var aStreams = <AudioFormat>[];
    if (json['audio_streams'] is List) {
      aStreams = (json['audio_streams'] as List)
          .map((a) => AudioFormat.fromJson(a))
          .toList();
    }

    var related = <VideoItem>[];
    if (json['related_videos'] is List) {
      related = (json['related_videos'] as List)
          .map((r) => VideoItem.fromJson(r))
          .toList();
    }

    var comms = <CommentItem>[];
    if (json['comments'] is List) {
      comms = (json['comments'] as List)
          .map((c) => CommentItem.fromJson(c))
          .toList();
    }

    return VideoDetails(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      channelName: json['channel_name'] ?? 'Unknown',
      channelId: json['channel_id'] ?? '',
      channelAvatar: json['channel_avatar'] ?? '',
      duration: json['duration'] is int ? json['duration'] : 0,
      viewCount: json['view_count'] is int ? json['view_count'] : 0,
      likeCount: json['like_count'] is int ? json['like_count'] : 0,
      uploadDate: json['upload_date'] ?? '',
      thumbnail: json['thumbnail'] ?? '',
      primaryStreamUrl: json['primary_stream_url'] ?? '',
      hlsManifestUrl: json['hls_manifest_url'],
      videoStreams: vStreams,
      audioStreams: aStreams,
      relatedVideos: related,
      comments: comms,
    );
  }
}

class ChannelProfile {
  final String id;
  final String title;
  final String description;
  final int subscriberCount;
  final String avatar;
  final String banner;
  final List<VideoItem> videos;
  final String handle;
  final String subscriberText;
  final String videoCountText;
  final bool isSubscribed;

  ChannelProfile({
    required this.id,
    required this.title,
    required this.description,
    required this.subscriberCount,
    required this.avatar,
    required this.banner,
    required this.videos,
    this.handle = '',
    this.subscriberText = '',
    this.videoCountText = '',
    this.isSubscribed = false,
  });

  factory ChannelProfile.fromJson(Map<String, dynamic> json) {
    var vids = <VideoItem>[];
    if (json['videos'] is List) {
      vids = (json['videos'] as List)
          .map((v) => VideoItem.fromJson(v))
          .toList();
    }

    return ChannelProfile(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      subscriberCount: json['subscriber_count'] is int ? json['subscriber_count'] : 0,
      avatar: json['avatar'] ?? '',
      banner: json['banner'] ?? '',
      videos: vids,
    );
  }
}

/// A filter chip from YouTube's feed header ("All", "Music", "Gaming", ...).
class FeedChip {
  final String title;
  final String? token;
  final bool selected;

  FeedChip({required this.title, this.token, this.selected = false});
}

/// One page of a YouTube feed plus the token to load the next page.
class FeedPage {
  final List<VideoItem> videos;
  final String? continuation;
  final List<FeedChip> chips;
  // True when [continuation] must be sent to the search endpoint (not browse).
  final bool fromSearch;

  FeedPage({required this.videos, this.continuation, this.chips = const [], this.fromSearch = false});

  static FeedPage empty() => FeedPage(videos: []);
}

class CommentPage {
  final List<CommentItem> comments;
  final String? continuation;

  CommentPage({required this.comments, this.continuation});
}

class AccountInfo {
  final String name;
  final String handle;
  final String avatar;

  AccountInfo({required this.name, required this.handle, required this.avatar});
}
