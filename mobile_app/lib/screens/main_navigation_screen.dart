import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../providers/player_provider.dart';
import '../widgets/player_panel.dart';
import 'home_screen.dart';
import 'shorts_screen.dart';
import 'subscriptions_screen.dart';
import 'library_screen.dart';

/// App shell, laid out like the YouTube app: each tab keeps its own page
/// stack, the bottom bar stays visible, and the player lives above everything
/// (full screen when expanded, a mini-player above the bottom bar otherwise).
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  static const int _shortsTab = 1;

  int _currentIndex = 0;
  final GlobalKey _stackKey = GlobalKey();
  Rect? _miniRect;
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  Widget _tabNavigator(int index, Widget root) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
    );
  }

  void _onTabTapped(int index) {
    final player = context.read<PlayerProvider>();
    player.minimize();
    if (index == _currentIndex) {
      // Re-tapping a tab goes back to its first page, like YouTube.
      _navigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _currentIndex = index);
  }

  Future<void> _handleBack() async {
    final player = context.read<PlayerProvider>();
    if (player.isFullscreen) {
      player.toggleFullscreen();
      return;
    }
    if (player.hasVideo && player.isExpanded) {
      player.minimize();
      return;
    }
    final nav = _navigatorKeys[_currentIndex].currentState;
    if (nav != null && await nav.maybePop()) return;
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return;
    }
    SystemNavigator.pop();
  }

  /// Finds the mini-player's video slot so the player surface can sit on it.
  void _measureMiniSlot() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final slot = MiniPlayer.videoSlotKey.currentContext?.findRenderObject() as RenderBox?;
      final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      Rect? rect;
      if (slot != null && stack != null && slot.attached && slot.hasSize) {
        rect = stack.globalToLocal(slot.localToGlobal(Offset.zero)) & slot.size;
      }
      if (rect != _miniRect) setState(() => _miniRect = rect);
    });
  }

  Widget _playerSurface(BuildContext context, bool showExpanded, bool showMini) {
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    // The web view always keeps its full size (resizing the page makes
    // YouTube's player pause); it is only scaled down for the mini-player.
    final full = context.read<PlayerProvider>().isFullscreen
        ? Offset.zero & size
        : Rect.fromLTWH(0, top, size.width, size.width * 9 / 16);
    Rect target;
    if (showExpanded) {
      target = full;
    } else if (showMini && _miniRect != null) {
      target = _miniRect!;
    } else {
      // Kept alive (so audio can continue) but out of sight.
      target = Rect.fromLTWH(-size.width * 2, size.height, 107, 60);
    }
    return TweenAnimationBuilder<Rect?>(
      tween: RectTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, rect, child) {
        final r = rect ?? target;
        return Positioned(
          left: r.left,
          top: r.top,
          width: full.width,
          height: full.height,
          child: Transform.scale(
            scale: r.width / full.width,
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
      child: PlayerSurface(mini: !showExpanded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final showMini = player.hasVideo && !player.isExpanded && _currentIndex != _shortsTab;
    final showExpanded = player.hasVideo && player.isExpanded;
    if (showMini) _measureMiniSlot();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            key: _stackKey,
            children: [
              Column(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: [
                        _tabNavigator(0, const HomeScreen()),
                        ShortsScreen(active: _currentIndex == _shortsTab && !showExpanded),
                        _tabNavigator(2, const SubscriptionsScreen()),
                        _tabNavigator(3, const LibraryScreen()),
                      ],
                    ),
                  ),
                  if (showMini) const MiniPlayer(),
                  _BottomBar(
                    currentIndex: _currentIndex,
                    onTap: _onTabTapped,
                    dark: _currentIndex == _shortsTab,
                  ),
                ],
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !showExpanded,
                  child: AnimatedSlide(
                    offset: showExpanded ? Offset.zero : const Offset(0, 1),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: showExpanded
                        ? ExpandedPlayer(tabNavigator: _navigatorKeys[_currentIndex].currentState)
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              if (player.hasVideo) _playerSurface(context, showExpanded, showMini),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool dark;

  const _BottomBar({required this.currentIndex, required this.onTap, required this.dark});

  @override
  Widget build(BuildContext context) {
    final bg = dark ? Colors.black : AppColors.background;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: const Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Theme(
          data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
          child: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: onTap,
            type: BottomNavigationBarType.fixed,
            backgroundColor: bg,
            elevation: 0,
            selectedItemColor: AppColors.textPrimary,
            unselectedItemColor: AppColors.textPrimary,
            selectedFontSize: 10.5,
            unselectedFontSize: 10.5,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.bolt_outlined),
                activeIcon: Icon(Icons.bolt),
                label: 'Shorts',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.subscriptions_outlined),
                activeIcon: Icon(Icons.subscriptions),
                label: 'Subscriptions',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_circle_outlined),
                activeIcon: Icon(Icons.account_circle),
                label: 'You',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
