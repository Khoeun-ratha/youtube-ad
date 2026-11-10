import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/app_theme.dart';
import '../core/navigation.dart';
import '../core/utils.dart';
import '../models/video_model.dart';
import '../providers/player_provider.dart';
import '../screens/channel_screen.dart';
import '../services/storage_service.dart';
import '../services/web_player.dart';
import 'video_card.dart';

/// Full-screen watch page (when expanded) for the app-wide player.
class ExpandedPlayer extends StatelessWidget {
  /// Navigator of the current tab, used to open channels under the panel.
  final NavigatorState? tabNavigator;

  const ExpandedPlayer({super.key, this.tabNavigator});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final video = player.currentVideo!;

    return Material(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            GestureDetector(
              // Swipe the video down to shrink it into the mini-player.
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 300) player.minimize();
              },
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: const _VideoViewport(),
              ),
            ),
            Expanded(
              child: _WatchDetails(
                key: ValueKey(video.id),
                player: player,
                video: video,
                tabNavigator: tabNavigator,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the video goes on the watch page. The video itself is drawn by
/// [PlayerSurface], which sits above the panel so it can move between here
/// and the mini-player without restarting playback.
class _VideoViewport extends StatelessWidget {
  const _VideoViewport();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

/// The one web view that plays the app-wide video, plus what's drawn over it.
///
/// [MainNavigationScreen] positions it over the watch page's video area when
/// expanded, or over the mini-player's thumbnail when minimized.
class PlayerSurface extends StatelessWidget {
  final bool mini;

  const PlayerSurface({super.key, required this.mini});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final video = player.currentVideo!;
    final error = player.errorMessage;
    final covered = player.isAudioOnly || (player.isLoading && !player.isPlaying) || error != null;

    return IgnorePointer(
      ignoring: mini,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          YouTubeWebView(player: player.web, bare: true),
          if (!mini && error == null) _PlayerControls(player: player),
          if (covered)
            IgnorePointer(
              ignoring: error == null && player.isAudioOnly && !player.isLoading,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(imageUrl: video.thumbnail, fit: BoxFit.cover),
                  Container(color: Colors.black45),
                  if (error != null && !mini)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.white, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                          TextButton(onPressed: player.retry, child: const Text('Retry')),
                        ],
                      ),
                    )
                  else if (player.isLoading && !player.isPlaying)
                    Center(
                      child: SizedBox.square(
                        dimension: mini ? 60 : 40,
                        child: CircularProgressIndicator(strokeWidth: mini ? 8 : 4, color: Colors.white),
                      ),
                    )
                  else if (player.isAudioOnly && !mini)
                    const Center(child: Icon(Icons.headphones, color: Colors.white70, size: 48)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The app's own controls over the video: tap to show/hide, play/pause,
/// seek bar, double-tap to skip 10s, settings and fullscreen.
class _PlayerControls extends StatefulWidget {
  final PlayerProvider player;

  const _PlayerControls({required this.player});

  @override
  State<_PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<_PlayerControls> {
  bool _visible = false;
  Timer? _hideTimer;
  double? _dragValue;
  String? _skipLabel;
  Timer? _skipTimer;

  WebPlayer get _web => widget.player.web;

  void _show() {
    setState(() => _visible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _web.isPlaying && _dragValue == null) setState(() => _visible = false);
    });
  }

  void _skip(int seconds) {
    final target = _web.position + Duration(seconds: seconds);
    _web.seek(target < Duration.zero ? Duration.zero : target);
    _skipTimer?.cancel();
    setState(() => _skipLabel = seconds > 0 ? '+${seconds}s' : '${seconds}s');
    _skipTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _skipLabel = null);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _skipTimer?.cancel();
    super.dispose();
  }

  static String _fmt(Duration d) => FormatUtils.formatDuration(d.inSeconds);

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _visible ? setState(() => _visible = false) : _show(),
        onDoubleTapDown: (d) => _skip(d.localPosition.dx < box.maxWidth / 2 ? -10 : 10),
        onDoubleTap: () {},
        onVerticalDragEnd: (d) {
          if (player.isFullscreen) return;
          if ((d.primaryVelocity ?? 0) > 300) player.minimize();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_skipLabel != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Text(_skipLabel!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !_visible,
                child: ListenableBuilder(
                  listenable: _web,
                  builder: (context, _) {
                    final total = _web.duration.inMilliseconds.toDouble();
                    final pos = (_dragValue ?? _web.position.inMilliseconds.toDouble())
                        .clamp(0.0, total > 0 ? total : 1.0);
                    return Container(
                      color: Colors.black45,
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            child: IconButton(
                              tooltip: player.isFullscreen ? 'Exit fullscreen' : 'Minimize',
                              icon: Icon(
                                player.isFullscreen ? Icons.fullscreen_exit : Icons.keyboard_arrow_down,
                                color: Colors.white,
                                size: 30,
                              ),
                              onPressed: player.isFullscreen ? player.toggleFullscreen : player.minimize,
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              tooltip: 'Settings',
                              icon: const Icon(Icons.settings_outlined, color: Colors.white),
                              onPressed: () => showPlayerSettings(context, player),
                            ),
                          ),
                          Center(
                            child: IconButton(
                              iconSize: 56,
                              icon: Icon(_web.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                              onPressed: () {
                                player.togglePlayPause();
                                _scheduleHide();
                              },
                            ),
                          ),
                          Positioned(
                            left: 12,
                            right: 0,
                            bottom: 0,
                            child: Row(
                              children: [
                                Text(
                                  '${_fmt(Duration(milliseconds: pos.round()))} / ${_fmt(_web.duration)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      overlayShape: SliderComponentShape.noOverlay,
                                      activeTrackColor: AppColors.primary,
                                      inactiveTrackColor: Colors.white30,
                                      thumbColor: AppColors.primary,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Slider(
                                        value: pos,
                                        max: total > 0 ? total : 1,
                                        onChanged: total > 0 ? (v) => setState(() => _dragValue = v) : null,
                                        onChangeEnd: (v) {
                                          _web.seek(Duration(milliseconds: v.round()));
                                          setState(() => _dragValue = null);
                                          _scheduleHide();
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Fullscreen',
                                  icon: Icon(
                                    player.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                    color: Colors.white,
                                  ),
                                  onPressed: player.toggleFullscreen,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchDetails extends StatefulWidget {
  final PlayerProvider player;
  final VideoItem video;
  final NavigatorState? tabNavigator;

  const _WatchDetails({super.key, required this.player, required this.video, this.tabNavigator});

  @override
  State<_WatchDetails> createState() => _WatchDetailsState();
}

class _WatchDetailsState extends State<_WatchDetails> {
  void _openChannel() {
    final v = widget.video;
    if (v.channelId.isEmpty) return;
    widget.player.minimize();
    final nav = widget.tabNavigator;
    if (nav != null) {
      nav.push(MaterialPageRoute(
        builder: (_) => ChannelScreen(channelId: v.channelId, channelName: v.channelName),
      ));
    } else {
      openChannel(context, v.channelId, v.channelName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final v = widget.video;
    final d = player.videoDetails;
    final related = d?.relatedVideos ?? const <VideoItem>[];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Title + meta
        InkWell(
          onTap: d == null ? null : () => _showDescription(context, d),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d?.title ?? v.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: [v.viewText, v.publishedText].where((e) => e.isNotEmpty).join('  ')),
                      const TextSpan(
                        text: '  ...more',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        // Channel row
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: _openChannel,
                child: ChannelAvatar(url: v.channelAvatar, name: v.channelName, radius: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _openChannel,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: v.channelName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (d != null && d.subscriberText.isNotEmpty)
                          TextSpan(
                            text: '  ${d.subscriberText.replaceAll(' subscribers', '')}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              _SubscribeButton(subscribed: player.isSubscribed, onPressed: player.toggleSubscribe),
            ],
          ),
        ),

        // Actions
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              _ActionPill(
                icon: player.isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                label: (d?.likeText.isNotEmpty ?? false) ? d!.likeText : 'Like',
                onTap: player.toggleLike,
              ),
              _ActionPill(icon: Icons.share_outlined, label: 'Share', onTap: () => copyVideoLink(context, v.id)),
              _ActionPill(
                icon: Icons.watch_later_outlined,
                label: 'Save',
                onTap: () async {
                  final added = await StorageService.toggleWatchLater(v);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(added ? 'Saved to Watch later' : 'Removed from Watch later')),
                    );
                  }
                },
              ),
              _ActionPill(
                icon: player.isAudioOnly ? Icons.videocam_outlined : Icons.headphones_outlined,
                label: player.isAudioOnly ? 'Video' : 'Audio only',
                onTap: player.toggleAudioOnly,
              ),
              _ActionPill(
                icon: Icons.hd_outlined,
                label: player.selectedQuality,
                onTap: () => showQualitySheet(context, player),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Comments preview
        if (d != null && d.commentsToken != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showComments(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Comments',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          TextSpan(
                            text: '  ${d.commentCountText}',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    if (player.comments.isNotEmpty)
                      Row(
                        children: [
                          ChannelAvatar(
                            url: player.comments.first.authorThumbnail,
                            name: player.comments.first.author,
                            radius: 12,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              player.comments.first.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        player.isLoadingComments || player.hasMoreComments ? 'Loading comments…' : 'No comments yet',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),

        // Up next
        if (d == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          )
        else
          ...related.where((r) => !r.isShort).map((r) => VideoCard(video: r)),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ],
    );
  }

  void _showDescription(BuildContext context, VideoDetails d) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Description',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: AppColors.divider, height: 24),
            Text(d.title,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(value: d.likeText.isNotEmpty ? d.likeText : '-', label: 'Likes'),
                _Stat(value: d.viewText.replaceAll(' views', ''), label: 'Views'),
                _Stat(value: d.publishedText, label: ''),
              ],
            ),
            const SizedBox(height: 16),
            SelectableText(
              d.description,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  void _showComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => ChangeNotifierProvider.value(
        value: widget.player,
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, controller) => Consumer<PlayerProvider>(
            builder: (context, p, _) {
              return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 600) p.loadMoreComments();
                  return false;
                },
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: p.comments.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Comments'),
                            TextSpan(
                              text: '  ${p.videoDetails?.commentCountText ?? ''}',
                              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.normal),
                            ),
                          ]),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                    if (i == p.comments.length + 1) {
                      return p.hasMoreComments || p.isLoadingComments
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                            )
                          : const SizedBox(height: 24);
                    }
                    return _CommentTile(comment: p.comments[i - 1]);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentItem comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChannelAvatar(url: comment.authorThumbnail, name: comment.author.replaceFirst('@', ''), radius: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${comment.author}  ·  ${comment.publishedText}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(comment.text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.35)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.thumb_up_outlined, size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(comment.likeText, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    if (comment.replyCount.isNotEmpty && comment.replyCount != '0') ...[
                      const SizedBox(width: 16),
                      Text(
                        '${comment.replyCount} replies',
                        style: const TextStyle(color: Color(0xFF3EA6FF), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
        if (label.isNotEmpty) Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class _SubscribeButton extends StatelessWidget {
  final bool subscribed;
  final VoidCallback onPressed;

  const _SubscribeButton({required this.subscribed, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: subscribed ? AppColors.chipBackground : AppColors.textPrimary,
        foregroundColor: subscribed ? AppColors.textPrimary : AppColors.background,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minimumSize: const Size(0, 36),
        shape: const StadiumBorder(),
      ),
      onPressed: onPressed,
      child: Text(subscribed ? 'Subscribed' : 'Subscribe', style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionPill({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: AppColors.chipBackground,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textPrimary),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini-player bar shown above the bottom navigation while browsing.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  static const double height = 62;

  /// Marks where the video sits in the bar, so [PlayerSurface] can line up.
  static final GlobalKey videoSlotKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final video = player.currentVideo!;

    return GestureDetector(
      onTap: player.expand,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -300) player.expand();
      },
      child: Material(
        color: AppColors.surface,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              ListenableBuilder(
                listenable: player.web,
                builder: (context, _) {
                  final total = player.web.duration.inMilliseconds;
                  final pos = player.web.position.inMilliseconds;
                  return LinearProgressIndicator(
                    value: total > 0 ? (pos / total).clamp(0.0, 1.0) : 0,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: AppColors.primary,
                  );
                },
              ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      key: videoSlotKey,
                      width: 107,
                      height: 60,
                      child: CachedNetworkImage(imageUrl: video.thumbnail, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            video.channelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (player.isLoading && !player.isPlaying)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary),
                        ),
                      )
                    else
                      IconButton(
                        icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, color: AppColors.textPrimary),
                        onPressed: player.togglePlayPause,
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textPrimary),
                      onPressed: player.close,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showPlayerSettings(BuildContext context, PlayerProvider player) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.tune, color: AppColors.textPrimary),
            title: const Text('Quality', style: TextStyle(color: AppColors.textPrimary)),
            trailing: Text(player.selectedQuality, style: const TextStyle(color: AppColors.textSecondary)),
            onTap: () {
              Navigator.pop(sheet);
              showQualitySheet(context, player);
            },
          ),
          ListTile(
            leading: const Icon(Icons.slow_motion_video, color: AppColors.textPrimary),
            title: const Text('Playback speed', style: TextStyle(color: AppColors.textPrimary)),
            trailing: Text('${player.speed}x', style: const TextStyle(color: AppColors.textSecondary)),
            onTap: () {
              Navigator.pop(sheet);
              _showSpeedSheet(context, player);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.headphones_outlined, color: AppColors.textPrimary),
            title: const Text('Audio only', style: TextStyle(color: AppColors.textPrimary)),
            value: player.isAudioOnly,
            activeThumbColor: AppColors.primary,
            onChanged: (_) {
              Navigator.pop(sheet);
              player.toggleAudioOnly();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.playlist_play, color: AppColors.textPrimary),
            title: const Text('Autoplay next video', style: TextStyle(color: AppColors.textPrimary)),
            value: player.autoplay,
            activeThumbColor: AppColors.primary,
            onChanged: (_) {
              Navigator.pop(sheet);
              player.toggleAutoplay();
            },
          ),
        ],
      ),
    ),
  );
}

void showQualitySheet(BuildContext context, PlayerProvider player) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Quality', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            for (final q in ['Auto', ...player.availableQualities])
              ListTile(
                title: Text(q, style: const TextStyle(color: AppColors.textPrimary)),
                trailing: player.selectedQuality == q ? const Icon(Icons.check, color: AppColors.primary) : null,
                onTap: () {
                  Navigator.pop(sheet);
                  player.switchQuality(q);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

void _showSpeedSheet(BuildContext context, PlayerProvider player) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
            ListTile(
              title: Text(s == 1.0 ? 'Normal' : '${s}x', style: const TextStyle(color: AppColors.textPrimary)),
              trailing: player.speed == s ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () {
                Navigator.pop(sheet);
                player.setSpeed(s);
              },
            ),
        ],
      ),
    ),
  );
}
