import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/app_theme.dart';
import '../models/video_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/video_card.dart';

class ChannelScreen extends StatefulWidget {
  final String channelId;
  final String channelName;

  const ChannelScreen({super.key, required this.channelId, required this.channelName});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final ApiService _apiService = ApiService();
  ChannelProfile? _profile;
  bool _isLoading = true;
  bool _isSubscribed = false;

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  Future<void> _loadChannel() async {
    final data = await _apiService.getChannelDetails(widget.channelId);
    final subscribed = _apiService.isSignedIn
        ? (data?.isSubscribed ?? false)
        : await StorageService.isSubscribed(data?.id ?? widget.channelId);
    if (mounted) {
      setState(() {
        _profile = data;
        _isSubscribed = subscribed;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSubscription() async {
    final id = _profile?.id ?? widget.channelId;
    setState(() => _isSubscribed = !_isSubscribed);
    if (_apiService.isSignedIn) {
      final ok = await _apiService.setSubscribed(id, _isSubscribed);
      if (!ok && mounted) setState(() => _isSubscribed = !_isSubscribed);
    } else {
      await StorageService.toggleSubscription(SubscribedChannel(
        id: id,
        name: _profile?.title ?? widget.channelName,
        avatar: _profile?.avatar ?? '',
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final regular = p?.videos.where((v) => !v.isShort).toList() ?? const <VideoItem>[];

    return Scaffold(
      appBar: AppBar(title: Text(p?.title ?? widget.channelName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.textPrimary))
          : p == null
              ? const Center(child: Text('Channel unavailable', style: TextStyle(color: AppColors.textSecondary)))
              : ListView.builder(
                  itemCount: regular.length + 1,
                  itemBuilder: (context, i) {
                    if (i > 0) return VideoCard(video: regular[i - 1]);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (p.banner.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AspectRatio(
                                aspectRatio: 6.2,
                                child: CachedNetworkImage(imageUrl: p.banner, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              ChannelAvatar(url: p.avatar, name: p.title, radius: 36),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.title,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [p.handle, p.subscriberText, p.videoCountText]
                                          .where((e) => e.isNotEmpty)
                                          .join(' · '),
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (p.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              p.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _isSubscribed ? AppColors.chipBackground : AppColors.textPrimary,
                                foregroundColor: _isSubscribed ? AppColors.textPrimary : AppColors.background,
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _toggleSubscription,
                              child: Text(
                                _isSubscribed ? 'Subscribed' : 'Subscribe',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            'Videos',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}
