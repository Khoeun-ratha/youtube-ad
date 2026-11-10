import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/feed_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/category_chips.dart';
import '../widgets/video_card.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'shorts_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surface,
          onRefresh: feed.refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 1500) feed.loadMore();
              return false;
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  snap: true,
                  titleSpacing: 14,
                  title: const AppLogo(),
                  actions: const [
                    _SearchButton(),
                    _AccountButton(),
                    SizedBox(width: 6),
                  ],
                  bottom: const PreferredSize(
                    preferredSize: Size.fromHeight(48),
                    child: CategoryChips(),
                  ),
                ),
                ..._buildFeed(context, feed),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFeed(BuildContext context, FeedProvider feed) {
    if (feed.isLoading && feed.videos.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
        ),
      ];
    }

    if (feed.errorMessage != null && feed.videos.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 56, color: Colors.white38),
                  const SizedBox(height: 16),
                  Text(
                    feed.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: feed.refresh, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final videos = feed.videos;
    // Like the app: a Shorts shelf after the first couple of videos.
    const shelfAt = 2;
    final hasShelf = feed.shorts.length >= 3 && videos.length > shelfAt;
    final count = videos.length + (hasShelf ? 1 : 0) + 1;

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i == count - 1) {
              return feed.hasMore
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
                    )
                  : const SizedBox(height: 24);
            }
            if (hasShelf && i == shelfAt) return ShortsShelf(shorts: feed.shorts);
            final index = hasShelf && i > shelfAt ? i - 1 : i;
            return VideoCard(video: videos[index]);
          },
          childCount: count,
        ),
      ),
    ];
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.search, size: 26),
      tooltip: 'Search',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final account = auth.account;
    return IconButton(
      tooltip: 'Account',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      icon: auth.isSignedIn && account != null
          ? ChannelAvatar(url: account.avatar, name: account.name, radius: 13)
          : const Icon(Icons.account_circle_outlined, size: 26),
    );
  }
}
