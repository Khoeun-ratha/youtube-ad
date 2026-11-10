import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/app_theme.dart';
import '../core/navigation.dart';
import '../models/video_model.dart';
import '../providers/player_provider.dart';
import '../services/api_service.dart';
import '../services/web_player.dart';
import '../widgets/video_card.dart';

/// The Shorts tab: loads a queue of Shorts and shows them in the vertical player.
class ShortsScreen extends StatefulWidget {
  final bool active;

  const ShortsScreen({super.key, required this.active});

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  List<VideoItem>? _shorts;
  bool _loading = false;

  @override
  void didUpdateWidget(covariant ShortsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _shorts == null) _load();
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final list = await ApiService().getShorts();
    if (mounted) {
      setState(() {
        _shorts = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shorts = _shorts;
    if (shorts == null || shorts.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text('Load Shorts', style: TextStyle(color: Colors.white)),
                ),
        ),
      );
    }
    return ShortsPlayerScreen(shorts: shorts, active: widget.active, showBack: false);
  }
}

/// Vertical swipe player for Shorts.
class ShortsPlayerScreen extends StatefulWidget {
  final List<VideoItem> shorts;
  final int initialIndex;
  final bool active;
  final bool showBack;

  const ShortsPlayerScreen({
    super.key,
    required this.shorts,
    this.initialIndex = 0,
    this.active = true,
    this.showBack = true,
  });

  @override
  State<ShortsPlayerScreen> createState() => _ShortsPlayerScreenState();
}

class _ShortsPlayerScreenState extends State<ShortsPlayerScreen> {
  final ApiService _api = ApiService();
  final WebPlayer _web = WebPlayer();
  late final PageController _pageController = PageController(initialPage: widget.initialIndex);
  final Map<String, Future<VideoDetails?>> _details = {};

  late int _index = widget.initialIndex;
  int _openToken = 0;
  bool _paused = false;
  StreamSubscription<void>? _endedSub;

  @override
  void initState() {
    super.initState();
    // Loop each Short, like YouTube.
    _endedSub = _web.onEnded.listen((_) {
      _web.seek(Duration.zero);
      _web.play();
    });
    if (widget.active) _start();
  }

  void _start() {
    // Shorts and the main player shouldn't play at the same time.
    context.read<PlayerProvider>().pause();
    // Coming back to the tab resumes the same Short instead of restarting it.
    if (_web.videoId == widget.shorts[_index].id && _web.hasStarted) {
      if (!_paused) _web.play();
    } else {
      _openIndex(_index);
    }
  }

  @override
  void didUpdateWidget(covariant ShortsPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _start();
      } else {
        _web.pause();
      }
    }
  }

  Future<VideoDetails?> _detailsFor(int i) =>
      _details.putIfAbsent(widget.shorts[i].id, () => _api.getVideoDetails(widget.shorts[i].id));

  Future<void> _openIndex(int i) async {
    final token = ++_openToken;
    _paused = false;
    await _web.load(widget.shorts[i].id, quality: '720p');
    // Fetch the details (channel, likes) for this one and the next.
    _detailsFor(i);
    if (i + 1 < widget.shorts.length) _detailsFor(i + 1);
    if (token == _openToken && mounted) setState(() {});
  }

  @override
  void dispose() {
    _openToken++;
    _endedSub?.cancel();
    _web.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            // Swipes are detected by each page (see _buildPage): touches over
            // the web view don't reliably reach a scrolling PageView.
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.shorts.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              _openIndex(i);
            },
            itemBuilder: (context, i) => _buildPage(widget.shorts[i], i == _index),
          ),
          SafeArea(
            child: Row(
              children: [
                if (widget.showBack)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 0, 12),
                    child: Text(
                      'Shorts',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _swipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 200) return;
    const duration = Duration(milliseconds: 250);
    if (v < 0 && _index + 1 < widget.shorts.length) {
      _pageController.nextPage(duration: duration, curve: Curves.easeOut);
    } else if (v > 0 && _index > 0) {
      _pageController.previousPage(duration: duration, curve: Curves.easeOut);
    }
  }

  Widget _buildPage(VideoItem short, bool isCurrent) {
    return GestureDetector(
      onVerticalDragEnd: _swipe,
      onTap: () {
        _web.playOrPause();
        setState(() => _paused = !_paused);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(imageUrl: short.thumbnail, fit: BoxFit.cover),
          if (isCurrent) ...[
            YouTubeWebView(player: _web, cover: true, bare: true),
            // Thumbnail until the Short starts, then a layer that keeps taps
            // and swipes in Flutter instead of the web page.
            ListenableBuilder(
              listenable: _web,
              builder: (context, _) => _web.hasStarted
                  ? const SizedBox.expand()
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(imageUrl: short.thumbnail, fit: BoxFit.cover),
                        const Center(child: CircularProgressIndicator(color: Colors.white)),
                      ],
                    ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _web.playOrPause();
                  setState(() => _paused = !_paused);
                },
              ),
            ),
          ],
          if (isCurrent && _paused)
            const Center(child: Icon(Icons.play_arrow, color: Colors.white70, size: 80)),
          // Bottom gradient for legibility.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 72,
            bottom: 24,
            child: FutureBuilder<VideoDetails?>(
              future: _detailsFor(widget.shorts.indexOf(short)),
              builder: (context, snap) {
                final d = snap.data;
                final channelName = d?.channelName ?? short.channelName;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (channelName.isNotEmpty)
                      Row(
                        children: [
                          ChannelAvatar(url: d?.channelAvatar ?? '', name: channelName, radius: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              channelName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    Text(
                      d?.title ?? short.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            right: 8,
            bottom: 24,
            child: FutureBuilder<VideoDetails?>(
              future: _detailsFor(widget.shorts.indexOf(short)),
              builder: (context, snap) {
                final d = snap.data;
                return Column(
                  children: [
                    _ShortsAction(icon: Icons.thumb_up, label: d?.likeText.isNotEmpty == true ? d!.likeText : 'Like'),
                    _ShortsAction(
                      icon: Icons.comment,
                      label: d?.commentCountText.isNotEmpty == true ? d!.commentCountText : 'Comments',
                    ),
                    _ShortsAction(
                      icon: Icons.share,
                      label: 'Share',
                      onTap: () => copyVideoLink(context, short.id),
                    ),
                  ],
                );
              },
            ),
          ),
          if (isCurrent)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ListenableBuilder(
                listenable: _web,
                builder: (context, _) {
                  final total = _web.duration.inMilliseconds;
                  final pos = _web.position.inMilliseconds;
                  return LinearProgressIndicator(
                    value: total > 0 ? (pos / total).clamp(0.0, 1.0) : 0,
                    minHeight: 2,
                    backgroundColor: Colors.white24,
                    color: AppColors.primary,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ShortsAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ShortsAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white12,
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Horizontal "Shorts" shelf shown inside feeds.
class ShortsShelf extends StatelessWidget {
  final List<VideoItem> shorts;

  const ShortsShelf({super.key, required this.shorts});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Row(
            children: [
              Icon(Icons.bolt, color: AppColors.primary, size: 26),
              SizedBox(width: 6),
              Text(
                'Shorts',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 300,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: shorts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final s = shorts[i];
              return GestureDetector(
                onTap: () => openVideo(context, s, shortsQueue: shorts),
                child: SizedBox(
                  width: 168,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: s.thumbnail,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(color: AppColors.surface),
                          errorWidget: (_, _, _) => Container(color: AppColors.surface),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.center,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              if (s.viewText.isNotEmpty)
                                Text(s.viewText, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
