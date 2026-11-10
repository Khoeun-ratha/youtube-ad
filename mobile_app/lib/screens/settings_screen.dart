import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/video_card.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final account = auth.account;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Account'),
          if (auth.isSignedIn)
            ListTile(
              leading: ChannelAvatar(url: account?.avatar ?? '', name: account?.name ?? '', radius: 20),
              title: Text(account?.name ?? 'Signed in', style: const TextStyle(color: AppColors.textPrimary)),
              subtitle: Text(
                account?.handle.isNotEmpty == true ? account!.handle : 'Google account',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: TextButton(
                onPressed: () async {
                  await context.read<AuthProvider>().signOut();
                  if (context.mounted) await onSignedIn(context);
                },
                child: const Text('Sign out', style: TextStyle(color: AppColors.primary)),
              ),
            )
          else
            ListTile(
              leading: const Icon(Icons.account_circle_outlined, color: AppColors.textPrimary, size: 36),
              title: const Text('Not signed in', style: TextStyle(color: AppColors.textPrimary)),
              subtitle: const Text(
                'Sign in to get your YouTube home feed, subscriptions, history and likes.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              trailing: SignInButton(onSignedIn: () => onSignedIn(context)),
            ),
          const Divider(color: AppColors.divider),
          const _Header('Playback'),
          ListTile(
            leading: const Icon(Icons.hd_outlined, color: AppColors.textPrimary),
            title: const Text('Default video quality', style: TextStyle(color: AppColors.textPrimary)),
            trailing: DropdownButton<String>(
              value: settings.preferredQuality,
              dropdownColor: AppColors.surface,
              underline: const SizedBox(),
              items: [
                for (final q in SettingsProvider.qualities)
                  DropdownMenuItem(value: q, child: Text(q, style: const TextStyle(color: AppColors.textPrimary))),
              ],
              onChanged: (q) {
                if (q != null) settings.updateQuality(q);
              },
            ),
          ),
          const Divider(color: AppColors.divider),
          const _Header('About'),
          const ListTile(
            leading: Icon(Icons.shield_outlined, color: AppColors.textPrimary),
            title: Text('No ads', style: TextStyle(color: AppColors.textPrimary)),
            subtitle: Text(
              'Videos are streamed straight from YouTube\'s media servers; ads are never requested.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;

  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
    );
  }
}
