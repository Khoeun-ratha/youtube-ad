import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/video_model.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/video_card.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

/// The "You" tab: account, history, Watch later, Liked videos.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final auth = context.watch<AuthProvider>();
    final account = auth.account;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.textPrimary,
        backgroundColor: AppColors.surface,
        onRefresh: library.loadLibrary,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: auth.isSignedIn
                  ? Row(
                      children: [
                        ChannelAvatar(url: account?.avatar ?? '', name: account?.name ?? '', radius: 34),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account?.name ?? 'Signed in',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if ((account?.handle ?? '').isNotEmpty)
                                Text(account!.handle, style: const TextStyle(color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enjoy your favorite videos',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Sign in to access videos that you\'ve liked or saved, and your YouTube history. '
                          'Without signing in, everything is kept on this phone only.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        SignInButton(onSignedIn: () => onSignedIn(context)),
                      ],
                    ),
            ),
            if (library.isLoadingLibrary)
              const LinearProgressIndicator(minHeight: 2, color: AppColors.textPrimary),
            _Section(
              title: 'History',
              videos: library.history,
              emptyText: 'Videos you watch will show up here',
              trailing: !auth.isSignedIn && library.history.isNotEmpty
                  ? TextButton(
                      onPressed: () => _confirmClearHistory(context, library),
                      child: const Text('Clear'),
                    )
                  : null,
            ),
            _Section(title: 'Watch later', videos: library.watchLater, emptyText: 'Save videos to watch later'),
            _Section(title: 'Liked videos', videos: library.likedVideos, emptyText: 'Videos you like show up here'),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory(BuildContext context, LibraryProvider library) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear watch history?'),
        content: const Text('This removes the history saved on this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              library.clearHistory();
            },
            child: const Text('Clear', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<VideoItem> videos;
  final String emptyText;
  final Widget? trailing;

  const _Section({required this.title, required this.videos, required this.emptyText, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (videos.isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => VideoListScreen(title: title, videos: videos),
                  )),
                  child: const Text('View all'),
                ),
              ?trailing,
            ],
          ),
        ),
        if (videos.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(emptyText, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          )
        else
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: videos.length.clamp(0, 20),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => SmallVideoCard(video: videos[i]),
            ),
          ),
      ],
    );
  }
}

class VideoListScreen extends StatelessWidget {
  final String title;
  final List<VideoItem> videos;

  const VideoListScreen({super.key, required this.title, required this.videos});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        itemCount: videos.length,
        itemBuilder: (context, i) => CompactVideoTile(video: videos[i]),
      ),
    );
  }
}
