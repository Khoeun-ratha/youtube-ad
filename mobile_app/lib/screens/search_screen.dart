import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/video_model.dart';
import '../providers/search_provider.dart';
import '../services/api_service.dart';
import '../widgets/video_card.dart';
import '../providers/player_provider.dart';
import 'shorts_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSearchSubmit(String val) async {
    final clean = val.trim();
    if (clean.isEmpty) return;

    final videoId = ApiService.extractVideoId(clean);
    if (videoId.isNotEmpty) {
      // A pasted YouTube link: play it directly.
      context.read<PlayerProvider>().playVideo(VideoItem(
        id: videoId,
        title: '',
        channelName: '',
        channelId: '',
        channelAvatar: '',
        duration: 0,
        viewCount: 0,
        uploadDate: '',
        thumbnail: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      ));
      return;
    }

    if (mounted) {
      Provider.of<SearchProvider>(context, listen: false).performSearch(clean);
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = Provider.of<SearchProvider>(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Container(
          height: 42,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search YouTube or paste a link',
              hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 18),
                      onPressed: () {
                        _controller.clear();
                        search.clearSearch();
                      },
                    )
                  : IconButton(
                      icon: const Icon(Icons.paste, color: AppColors.primary, size: 18),
                      tooltip: 'Paste from clipboard',
                      onPressed: () async {
                        final clip = await Clipboard.getData('text/plain');
                        if (clip?.text != null && clip!.text!.isNotEmpty) {
                          _controller.text = clip.text!;
                          setState(() {});
                          _handleSearchSubmit(clip.text!);
                        }
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: InputBorder.none,
            ),
            onChanged: (val) {
              setState(() {});
              search.onQueryChanged(val);
            },
            onSubmitted: _handleSearchSubmit,
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          if (search.isLoading) {
            return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));
          }

          // If search was executed, show results
          if (search.hasSearched) {
            if (search.searchResults.isEmpty) {
              return const Center(
                child: Text('No results found.', style: TextStyle(color: AppColors.textSecondary)),
              );
            }
            final shorts = search.searchResults.where((v) => v.isShort).toList();
            final videos = search.searchResults.where((v) => !v.isShort).toList();
            const shelfAt = 3;
            final hasShelf = shorts.length >= 3 && videos.length > shelfAt;
            return NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 1500) search.loadMore();
                return false;
              },
              child: ListView.builder(
                itemCount: videos.length + (hasShelf ? 1 : 0) + 1,
                itemBuilder: (context, i) {
                  if (i == videos.length + (hasShelf ? 1 : 0)) {
                    return search.hasMore
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
                          )
                        : const SizedBox(height: 24);
                  }
                  if (hasShelf && i == shelfAt) return ShortsShelf(shorts: shorts);
                  return VideoCard(video: videos[hasShelf && i > shelfAt ? i - 1 : i]);
                },
              ),
            );
          }

          // If user is typing and suggestions are available
          if (search.suggestions.isNotEmpty) {
            return ListView.builder(
              itemCount: search.suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = search.suggestions[index];
                return ListTile(
                  leading: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                  title: Text(suggestion, style: const TextStyle(color: AppColors.textPrimary)),
                  trailing: const Icon(Icons.north_west, color: AppColors.textSecondary, size: 16),
                  onTap: () {
                    _controller.text = suggestion;
                    _handleSearchSubmit(suggestion);
                  },
                );
              },
            );
          }

          // Otherwise show Recent Searches
          if (search.recentSearches.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Searches',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      TextButton(
                        onPressed: search.clearAllRecentSearches,
                        child: const Text('Clear All', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: search.recentSearches.length,
                    itemBuilder: (context, index) {
                      final item = search.recentSearches[index];
                      return ListTile(
                        leading: const Icon(Icons.history, color: AppColors.textSecondary, size: 20),
                        title: Text(item, style: const TextStyle(color: AppColors.textPrimary)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 18),
                          onPressed: () => search.removeRecentSearch(item),
                        ),
                        onTap: () {
                          _controller.text = item;
                          _handleSearchSubmit(item);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          }

          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search, size: 64, color: Colors.white24),
                SizedBox(height: 12),
                Text(
                  'Search YouTube or paste a video link',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
