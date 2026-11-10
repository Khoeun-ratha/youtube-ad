import '../models/video_model.dart';

class FormatUtils {
  static String formatDuration(int seconds) {
    if (seconds <= 0) return "0:00";
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  static String formatViews(int count) {
    if (count <= 0) return "0 views";
    if (count >= 1000000000) {
      return '${(count / 1000000000).toStringAsFixed(1)}B views';
    } else if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M views';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K views';
    } else {
      return '$count views';
    }
  }

  static String formatLikes(int count) {
    if (count <= 0) return "Like";
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return '$count';
    }
  }

  static String formatSubs(int count) {
    if (count <= 0) return "Subscribers";
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M subscribers';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K subscribers';
    } else {
      return '$count subscribers';
    }
  }

  static String formatUploadDate(String dateStr) {
    if (dateStr.length == 8) {
      try {
        final year = int.parse(dateStr.substring(0, 4));
        final month = int.parse(dateStr.substring(4, 6));
        final day = int.parse(dateStr.substring(6, 8));
        final dt = DateTime(year, month, day);
        final diff = DateTime.now().difference(dt);
        if (diff.inDays > 365) {
          return '${(diff.inDays / 365).floor()} years ago';
        } else if (diff.inDays > 30) {
          return '${(diff.inDays / 30).floor()} months ago';
        } else if (diff.inDays > 0) {
          return '${diff.inDays} days ago';
        } else {
          return 'Today';
        }
      } catch (_) {}
    }
    return dateStr;
  }

  /// "Channel · 1.2M views · 3 days ago" using YouTube's own text when we have it.
  static String videoMeta(VideoItem v, {bool includeChannel = true}) {
    final parts = <String>[
      if (includeChannel && v.channelName.isNotEmpty) v.channelName,
      if (v.viewText.isNotEmpty) v.viewText else if (v.viewCount > 0) formatViews(v.viewCount),
      if (v.publishedText.isNotEmpty)
        v.publishedText
      else if (v.uploadDate.isNotEmpty)
        formatUploadDate(v.uploadDate),
    ];
    return parts.join(' · ');
  }
}
