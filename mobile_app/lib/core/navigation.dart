import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/video_model.dart';
import '../providers/player_provider.dart';
import '../screens/channel_screen.dart';
import '../screens/shorts_screen.dart';

/// Opens a video the way the YouTube app does: regular videos in the
/// player panel, Shorts in the vertical Shorts player.
void openVideo(BuildContext context, VideoItem video, {List<VideoItem>? shortsQueue}) {
  if (video.isShort) {
    final queue = shortsQueue ?? [video];
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ShortsPlayerScreen(
          shorts: queue,
          initialIndex: queue.indexWhere((v) => v.id == video.id).clamp(0, queue.length - 1),
        ),
      ),
    );
    return;
  }
  context.read<PlayerProvider>().playVideo(video);
}

void openChannel(BuildContext context, String channelId, String channelName) {
  if (channelId.isEmpty) return;
  context.read<PlayerProvider>().minimize();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChannelScreen(channelId: channelId, channelName: channelName),
    ),
  );
}

Future<void> copyVideoLink(BuildContext context, String videoId) async {
  await Clipboard.setData(ClipboardData(text: 'https://youtu.be/$videoId'));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }
}
