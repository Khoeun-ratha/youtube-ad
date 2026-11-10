import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../core/navigation.dart';
import '../providers/library_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/video_card.dart';
import 'login_screen.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const AppLogo(),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: library.refreshSubscriptions),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.textPrimary,
        backgroundColor: AppColors.surface,
        onRefresh: library.refreshSubscriptions,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 1500) {
              library.loadMoreSubscriptions();
            }
            return false;
          },
          child: _buildBody(context, library),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LibraryProvider library) {
    if (library.subscriptions.isEmpty && !library.isLoadingSubscriptions) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.subscriptions_outlined, size: 72, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'Don\'t miss new videos',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              library.isSignedIn
                  ? 'Subscribe to channels to see their latest videos here.'
                  : 'Sign in to see updates from your YouTube subscriptions, or subscribe to channels in the app.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          if (!library.isSignedIn) ...[
            const SizedBox(height: 20),
            Center(child: SignInButton(onSignedIn: () => onSignedIn(context))),
          ],
        ],
      );
    }

    return ListView(
      children: [
        SizedBox(
          height: 98,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: library.subscriptions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final ch = library.subscriptions[index];
              return GestureDetector(
                onTap: () => openChannel(context, ch.id, ch.name),
                child: SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      ChannelAvatar(url: ch.avatar, name: ch.name, radius: 28),
                      const SizedBox(height: 6),
                      Text(
                        ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(color: AppColors.divider, height: 1),
        if (library.isLoadingSubscriptions && library.subscriptionVideos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
          )
        else
          ...library.subscriptionVideos.map((v) => VideoCard(video: v)),
        if (library.isLoadingMoreSubscriptions)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
          ),
      ],
    );
  }
}
