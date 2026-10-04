import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/theme/theme_provider.dart';
import '../core/widgets/cached_network_image.dart';
import '../twitter/auth/app_controller.dart';
import 'app_drawer.dart';
import 'login_page.dart';
import 'timeline_page.dart';
import 'discovery_pages.dart';
import 'settings_pane.dart';
import '../core/services/notification_poll.dart';
import 'compose_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  int _homeTimelineIndex = 0;
  final Set<int> _visited = {0};
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _openingNotifications = false;
  final Set<int> _visitedHomeTimelineTabs = {0};
  late final TabController _homeTimelineController;
  final ScrollPageActions _forYouActions = ScrollPageActions();
  final ScrollPageActions _followingActions = ScrollPageActions();
  final ScrollPageActions _exploreActions = ScrollPageActions();
  DateTime? _lastNavigationTapTime;
  Timer? _navigationSingleTapTimer;
  int? _pendingNavigationTapIndex;
  DateTime? _lastTopBarTapTime;
  Timer? _topBarSingleTapTimer;
  @override
  void initState() {
    super.initState();
    _homeTimelineController = TabController(length: 2, vsync: this)
      ..addListener(_onHomeTimelineChanged);
    NotificationPoll.channel.setMethodCallHandler((call) async {
      if (call.method == 'openNotifications' && mounted) {
        _openNotifications();
      }
    });
    _consumeLaunch();
  }

  void _onHomeTimelineChanged() {
    final index = _homeTimelineController.index;
    if (index == _homeTimelineIndex) return;
    _homeTimelineIndex = index;
    _visitedHomeTimelineTabs.add(index);
    if (mounted) setState(() {});
  }

  ScrollPageActions? _actionsForNavigationIndex(int index) {
    if (index == 0) {
      return _homeTimelineIndex == 1 ? _followingActions : _forYouActions;
    }
    if (index == 1) return _exploreActions;
    return null;
  }

  void _cancelPendingTapGestures() {
    _navigationSingleTapTimer?.cancel();
    _navigationSingleTapTimer = null;
    _lastNavigationTapTime = null;
    _pendingNavigationTapIndex = null;
    _topBarSingleTapTimer?.cancel();
    _topBarSingleTapTimer = null;
    _lastTopBarTapTime = null;
  }

  void _onNavigationItemSelected(int index) {
    if (index != _tab) {
      _cancelPendingTapGestures();
      setState(() {
        _tab = index;
        _visited.add(index);
      });
      return;
    }

    final actions = _actionsForNavigationIndex(index);
    if (actions == null) return;

    final now = DateTime.now();
    if (_pendingNavigationTapIndex == index &&
        _lastNavigationTapTime != null &&
        now.difference(_lastNavigationTapTime!) <
            const Duration(milliseconds: 300)) {
      _navigationSingleTapTimer?.cancel();
      _navigationSingleTapTimer = null;
      _lastNavigationTapTime = null;
      _pendingNavigationTapIndex = null;
      actions.handleDoubleTap();
      return;
    }

    _navigationSingleTapTimer?.cancel();
    _lastNavigationTapTime = now;
    _pendingNavigationTapIndex = index;
    _navigationSingleTapTimer = Timer(const Duration(milliseconds: 300), () {
      _lastNavigationTapTime = null;
      _pendingNavigationTapIndex = null;
      if (mounted && _tab == index) {
        _actionsForNavigationIndex(index)?.handleSingleTap();
      }
    });
  }

  void _onTopBarTap() {
    HapticFeedbackUtil.light();
    final now = DateTime.now();
    if (_lastTopBarTapTime != null &&
        now.difference(_lastTopBarTapTime!) <
            const Duration(milliseconds: 300)) {
      _topBarSingleTapTimer?.cancel();
      _topBarSingleTapTimer = null;
      _lastTopBarTapTime = null;
      if (_tab == 0) {
        _actionsForNavigationIndex(0)?.handleTopBarDoubleTap();
      } else if (_tab == 1) {
        _exploreActions.handleTopBarDoubleTap();
      }
    } else {
      _lastTopBarTapTime = now;
      _topBarSingleTapTimer?.cancel();
      _topBarSingleTapTimer = Timer(const Duration(milliseconds: 300), () {
        _lastTopBarTapTime = null;
      });
    }
  }

  Future<void> _consumeLaunch() async {
    try {
      final open = await NotificationPoll.channel
          .invokeMethod<bool>('consumeOpenNotifications');
      if (open == true && mounted) {
        _openNotifications();
      }
    } catch (_) {}
  }

  void _openNotifications() {
    if (!mounted || _openingNotifications) return;
    _openingNotifications = true;
    Navigator.of(context)
        .push(
            MaterialPageRoute<void>(builder: (_) => const NotificationsPage()))
        .whenComplete(() => _openingNotifications = false);
  }

  @override
  void dispose() {
    _cancelPendingTapGestures();
    NotificationPoll.channel.setMethodCallHandler(null);
    _homeTimelineController
      ..removeListener(_onHomeTimelineChanged)
      ..dispose();
    super.dispose();
  }

  void _login() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const LoginPage()));
  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider),
        theme = ref.watch(themeProvider);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final standardNavBar = NavigationBar(
        selectedIndex: _tab,
        elevation: 0,
        height: 68,
        onDestinationSelected: _onNavigationItemSelected,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: '首页'),
          NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: '探索'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: '设置'),
        ]);
    final floatingCapsuleBar = Container(
      width: 280,
      height: 64,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildCapsuleItem(
            index: 0,
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: '首页',
            colorScheme: colorScheme,
          ),
          _buildCapsuleItem(
            index: 1,
            icon: Icons.explore_outlined,
            selectedIcon: Icons.explore,
            label: '探索',
            colorScheme: colorScheme,
          ),
          _buildCapsuleItem(
            index: 2,
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: '设置',
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
    final appBar = AppBar(
        leading: IconButton(
            tooltip: '打开侧边栏',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: controller.me?.avatar.isNotEmpty == true
                ? ClipOval(
                    child: CachedNetworkImage(controller.me!.avatar,
                        width: 32, height: 32, fit: BoxFit.cover))
                : const Icon(Icons.menu_rounded)),
        title: Text(const ['ReviewX', '探索', '设置'][_tab]),
        bottom: controller.loggedIn && _tab == 0
            ? TabBar(
                controller: _homeTimelineController,
                tabs: const [
                  Tab(text: '为你推荐'),
                  Tab(text: '正在关注'),
                ],
              )
            : null,
        actions: [
          if (controller.loggedIn && _tab == 0)
            IconButton(
                tooltip: '发布帖子',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ComposePage()))),
        ]);
    return Scaffold(
        key: _scaffoldKey,
        drawer: const AppDrawer(),
        extendBody: theme.useFloatingNavBar,
        appBar: PreferredSize(
            preferredSize: appBar.preferredSize,
            child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _onTopBarTap,
                child: appBar)),
        body: Column(children: [
          if (controller.expired)
            MaterialBanner(content: const Text('X 会话已过期，请重新登录'), actions: [
              TextButton(onPressed: _login, child: const Text('重新登录'))
            ]),
          Expanded(
              child: _tab == 2
                  ? const SettingsPane()
                  : controller.loggedIn
                      ? IndexedStack(
                          key: ValueKey(controller.epoch),
                          index: _tab,
                          children: [
                              TabBarView(
                                controller: _homeTimelineController,
                                children: [
                                  TimelinePage(
                                      cacheKey: 'for_you',
                                      actions: _forYouActions,
                                      load: (cursor) => controller.adapter
                                          .forYou(cursor: cursor)),
                                  _visitedHomeTimelineTabs.contains(1)
                                      ? TimelinePage(
                                          cacheKey: 'following',
                                          actions: _followingActions,
                                          load: (cursor) => controller.adapter
                                              .following(cursor: cursor))
                                      : const SizedBox.shrink(),
                                ],
                              ),
                              _visited.contains(1)
                                  ? SearchPage(
                                      showExplore: true,
                                      actions: _exploreActions,
                                    )
                                  : const SizedBox.shrink(),
                            ])
                      : Center(
                          child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.forum_outlined,
                                        size: 72,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    const SizedBox(height: 24),
                                    Text('ReviewX',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineLarge),
                                    const SizedBox(height: 12),
                                    const Text('登录 X，阅读你的关注时间线',
                                        textAlign: TextAlign.center),
                                    const SizedBox(height: 24),
                                    FilledButton.icon(
                                        onPressed: _login,
                                        icon: const Icon(Icons.login),
                                        label: const Text('登录 X'))
                                  ]))))
        ]),
        bottomNavigationBar: theme.useFloatingNavBar
            ? SafeArea(
                child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: 1,
                    child: Padding(
                        padding:
                            EdgeInsets.only(bottom: bottomPadding > 0 ? 6 : 14),
                        child: floatingCapsuleBar)))
            : standardNavBar);
  }

  Widget _buildCapsuleItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _tab == index;
    final activeBackground = colorScheme.secondaryContainer;
    final activeForeground = colorScheme.onSecondaryContainer;
    final inactiveForeground = colorScheme.onSurfaceVariant;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: () => _onNavigationItemSelected(index),
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (isSelected)
                TweenAnimationBuilder<double>(
                  key: ValueKey(index),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: activeBackground,
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSelected ? selectedIcon : icon,
                    size: 22,
                    color: isSelected ? activeForeground : inactiveForeground,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: context.adjustWeight(
                          isSelected ? FontWeight.w600 : FontWeight.w400),
                      color: isSelected ? activeForeground : inactiveForeground,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
