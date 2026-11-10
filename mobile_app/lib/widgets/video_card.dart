import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/app_theme.dart';
import '../core/navigation.dart';
import '../core/utils.dart';
import '../models/video_model.dart';
import '../services/storage_service.dart';

/// Full-width feed card (thumbnail on top, avatar + title + meta below).
class VideoCard extends StatelessWidget {
  final VideoItem video;

  const VideoCard({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openVideo(context, video),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VideoThumbnail(video: video),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => openChannel(context, video.channelId, video.channelName),
                  child: ChannelAvatar(url: video.channelAvatar, name: video.channelName, radius: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        FormatUtils.videoMeta(video),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textPrimary),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showVideoOptions(context, video),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact row (small thumbnail left), used for history and playlists.
class CompactVideoTile extends StatelessWidget {
  final VideoItem video;

  const CompactVideoTile({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openVideo(context, video),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: VideoThumbnail(video: video),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    FormatUtils.videoMeta(video),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textPrimary),
              visualDensity: VisualDensity.compact,
              onPressed: () => showVideoOptions(context, video),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small card for horizontal rows (history, watch later on the You tab).
class SmallVideoCard extends StatelessWidget {
  final VideoItem video;

  const SmallVideoCard({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: InkWell(
        onTap: () => openVideo(context, video),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: VideoThumbnail(video: video),
            ),
            const SizedBox(height: 6),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            Text(
              video.channelName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoThumbnail extends StatelessWidget {
  final VideoItem video;

  const VideoThumbnail({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: video.thumbnail,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: AppColors.surface),
            errorWidget: (context, url, error) => Container(
              color: AppColors.surface,
              child: const Icon(Icons.play_circle_outline, color: Colors.white24, size: 40),
            ),
          ),
          if (video.isLive || video.duration > 0)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: video.isLive ? AppColors.primary : Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (video.isLive) ...[
                      const Icon(Icons.sensors, color: Colors.white, size: 12),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      video.isLive ? 'LIVE' : FormatUtils.formatDuration(video.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ChannelAvatar extends StatelessWidget {
  final String url;
  final String name;
  final double radius;

  const ChannelAvatar({super.key, required this.url, required this.name, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.surfaceLight,
      backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
      child: url.isEmpty
          ? Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: radius * 0.8),
            )
          : null,
    );
  }
}

void showVideoOptions(BuildContext context, VideoItem video) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.watch_later_outlined, color: AppColors.textPrimary),
              title: const Text('Save to Watch later', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final added = await StorageService.toggleWatchLater(video);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(added ? 'Saved to Watch later' : 'Removed from Watch later')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: AppColors.textPrimary),
              title: const Text('Share', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                copyVideoLink(context, video.id);
              },
            ),
            if (video.channelId.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.account_circle_outlined, color: AppColors.textPrimary),
                title: const Text('Go to channel', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  openChannel(context, video.channelId, video.channelName);
                },
              ),
          ],
        ),
      );
    },
  );
}
