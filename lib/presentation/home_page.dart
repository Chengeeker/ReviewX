import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart' show kTouchSlop, VelocityTracker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/navigation/x_deep_link.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/theme/theme_provider.dart';
import '../core/widgets/cached_network_image.dart';
import '../core/widgets/frosted_app_bar.dart';
import '../twitter/auth/app_controller.dart';
import 'app_drawer.dart';
import 'login_page.dart';
import 'timeline_page.dart';
import 'discovery_pages.dart';
import 'settings_pane.dart';
import '../core/services/notification_poll.dart';
import 'compose_page.dart';
import 'x_profile_link_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin {
  int _tab = 0;
  int _homeTimelineIndex = 0;
  final Set<int> _visited = {0};
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _openingNotifications = false;
  final Set<int> _visitedHomeTimelineTabs = {0};
  late final TabController _homeTimelineController;
  late final AnimationController _tabTransitionController;
  late final CurvedAnimation _tabTransitionCurve;
  late Animation<Offset> _tabIncomingTransition;
  late Animation<Offset> _tabOutgoingTransition;
  int _previousTab = 0;
  bool _isTabTransitioning = false;
  final ScrollPageActions _forYouActions = ScrollPageActions();
  final ScrollPageActions _followingActions = ScrollPageActions();
  final ScrollPageActions _exploreActions = ScrollPageActions();
  final TextEditingController _exploreSearchController =
      TextEditingController();
  final FocusNode _exploreSearchFocus = FocusNode();
  bool _explorePersonalized = true;
  DateTime? _lastNavigationTapTime;
  Timer? _navigationSingleTapTimer;
  int? _pendingNavigationTapIndex;
  DateTime? _lastTopBarTapTime;
  Timer? _topBarSingleTapTimer;
  String? _lastDeepLink;
  DateTime? _lastDeepLinkTime;
  @override
  void initState() {
    super.initState();
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );
    _tabTransitionCurve = CurvedAnimation(
      parent: _tabTransitionController,
      curve: Curves.easeOutCubic,
    );
    _tabIncomingTransition = const AlwaysStoppedAnimation(Offset.zero);
    _tabOutgoingTransition = const AlwaysStoppedAnimation(Offset.zero);
    _tabTransitionController.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _isTabTransitioning &&
          mounted) {
        setState(() => _isTabTransitioning = false);
      }
    });
    _homeTimelineController = TabController(length: 2, vsync: this)
      ..addListener(_onHomeTimelineChanged);
    NotificationPoll.channel.setMethodCallHandler((call) async {
      if (call.method == 'openNotifications' && mounted) {
        _openNotifications();
      }
    });
    XDeepLinkChannel.setHandler((link) async {
      if (!mounted) return false;
      await _openXLink(link);
      return true;
    });
    _consumeLaunch();
    _consumeInitialXLink();
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
      _selectTab(index);
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
        _topBarSingleTapTimer = null;
        if (mounted && _tab == 0) {
          _actionsForNavigationIndex(0)?.handleTopBarSingleTap();
        }
      });
    }
  }

  void _selectTab(int index) {
    if (index == _tab) {
      if (!_visited.contains(index)) setState(() => _visited.add(index));
      return;
    }

    if (_tab == 1 && index != 1) _exploreSearchFocus.unfocus();
    _cancelPendingTapGestures();
    if (MediaQuery.disableAnimationsOf(context)) {
      _tabTransitionController.stop();
      setState(() {
        _previousTab = index;
        _tab = index;
        _visited.add(index);
        _isTabTransitioning = false;
        _tabIncomingTransition = const AlwaysStoppedAnimation(Offset.zero);
        _tabOutgoingTransition = const AlwaysStoppedAnimation(Offset.zero);
      });
      _tabTransitionController.value = 1;
      return;
    }

    final currentOffset =
        _isTabTransitioning ? _tabIncomingTransition.value : Offset.zero;
    var direction = index > _tab ? 1.0 : -1.0;
    if (Directionality.of(context) == TextDirection.rtl) direction *= -1;
    setState(() {
      _previousTab = _tab;
      _tab = index;
      _visited.add(index);
      _isTabTransitioning = true;
      _tabIncomingTransition = Tween<Offset>(
        begin: Offset(direction, 0),
        end: Offset.zero,
      ).animate(_tabTransitionCurve);
      _tabOutgoingTransition = Tween<Offset>(
        begin: currentOffset,
        end: Offset(-direction, 0),
      ).animate(_tabTransitionCurve);
    });
    _tabTransitionController.forward(from: 0);
  }

  Widget _buildTabContent(List<Widget> pages) {
    final pageOrder = List<int>.generate(pages.length, (index) => index)
      ..sort((a, b) => _tabPageLayer(a).compareTo(_tabPageLayer(b)));
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final index in pageOrder)
          Positioned.fill(
            key: ValueKey(index),
            child: Offstage(
              offstage: index != _tab &&
                  (!_isTabTransitioning || index != _previousTab),
              child: TickerMode(
                enabled: index == _tab ||
                    (_isTabTransitioning && index == _previousTab),
                child: IgnorePointer(
                  ignoring: index != _tab,
                  child: SlideTransition(
                    position: index == _tab
                        ? _tabIncomingTransition
                        : index == _previousTab && _isTabTransitioning
                            ? _tabOutgoingTransition
                            : const AlwaysStoppedAnimation(Offset.zero),
                    child: pages[index],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  int _tabPageLayer(int index) {
    if (_isTabTransitioning && index == _previousTab) return 1;
    if (index == _tab) return 2;
    return 0;
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

  Future<void> _consumeInitialXLink() async {
    try {
      final link = await XDeepLinkChannel.consumeInitialLink();
      if (link != null && mounted) await _openXLink(link);
    } catch (_) {}
  }

  Future<void> _openXLink(String value) async {
    final target = XLinkTarget.parse(value);
    if (target == null || !mounted) return;
    final now = DateTime.now();
    if (_lastDeepLink == value &&
        _lastDeepLinkTime != null &&
        now.difference(_lastDeepLinkTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastDeepLink = value;
    _lastDeepLinkTime = now;

    final controller = ref.read(appControllerProvider);
    final requiresLogin = const {
      XLinkKind.post,
      XLinkKind.profile,
      XLinkKind.search,
      XLinkKind.notifications,
      XLinkKind.bookmarks,
    }.contains(target.kind);
    if (requiresLogin && !controller.loggedIn) {
      _login();
      return;
    }

    void openPage(Widget page) {
      unawaited(Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page)));
    }

    switch (target.kind) {
      case XLinkKind.post:
        openPage(PostDetailPage.fromId(postId: target.postId!));
      case XLinkKind.profile:
        openPage(XProfileLinkPage(handle: target.handle!));
      case XLinkKind.home:
      case XLinkKind.explore:
        final tab = target.kind == XLinkKind.explore ? 1 : 0;
        _cancelPendingTapGestures();
        _selectTab(tab);
      case XLinkKind.search:
        final query = target.query?.trim() ?? '';
        openPage(SearchPage(initialQuery: query, showExplore: query.isEmpty));
      case XLinkKind.notifications:
        _openNotifications();
      case XLinkKind.bookmarks:
        openPage(const AccountHistoryPage());
      case XLinkKind.other:
        try {
          final opened =
              await launchUrl(target.uri, mode: LaunchMode.inAppBrowserView);
          if (!opened && mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('无法在应用内打开此 X 链接')));
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('无法在应用内打开此 X 链接')));
          }
        }
    }
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
    XDeepLinkChannel.clearHandler();
    _homeTimelineController
      ..removeListener(_onHomeTimelineChanged)
      ..dispose();
    _tabTransitionCurve.dispose();
    _tabTransitionController.dispose();
    _exploreSearchController.dispose();
    _exploreSearchFocus.dispose();
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
    final materialTheme = Theme.of(context);
    final colorScheme = materialTheme.colorScheme;
    final useLiquidGlassNavigation =
        theme.useFloatingNavBar && theme.useLiquidGlass;
    final floatingNavWidth =
        math.min(440.0, MediaQuery.sizeOf(context).width - 40.0) * 2 / 3;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final standardNavBar = NavigationBarTheme(
      data: AppTheme.scaleNavigationBarTheme(
        materialTheme.navigationBarTheme,
        MediaQuery.textScalerOf(context),
      ),
      child: NavigationBar(
        selectedIndex: _tab,
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
        ],
      ),
    );
    final floatingCapsuleBar = Container(
      width: floatingNavWidth,
      height: 56,
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
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              alignment: Alignment(_tab - 1.0, 0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOutCubic,
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),
          ),
          Row(
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
        ],
      ),
    );
    final appBar = buildFrostedAppBar(
      context,
      automaticallyImplyLeading: false,
      toolbarHeight:
          controller.loggedIn && _tab == 0 ? kToolbarHeight - 8 : null,
      leading: _tab == 0
          ? IconButton(
              tooltip: '打开侧边栏',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: controller.me?.avatar.isNotEmpty == true
                  ? ClipOval(
                      child: CachedNetworkImage(controller.me!.avatar,
                          width: 32, height: 32, fit: BoxFit.cover))
                  : const Icon(Icons.menu_rounded))
          : null,
      title: _tab == 0
          ? const Text('ReviewX')
          : _tab == 1
              ? TextField(
                  controller: _exploreSearchController,
                  focusNode: _exploreSearchFocus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _exploreActions.submitSearch,
                  decoration: InputDecoration(
                    hintText: '搜索 X',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: () => _exploreActions
                          .submitSearch(_exploreSearchController.text),
                    ),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(32),
                      borderSide: BorderSide.none,
                    ),
                  ),
                )
              : null,
      bottom: controller.loggedIn && _tab == 0
          ? TabBar(
              controller: _homeTimelineController,
              tabs: const [
                Tab(text: '为你推荐'),
                Tab(text: '正在关注'),
              ],
            )
          : _tab == 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Row(
                    children: [
                      for (final personalized in [true, false])
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (_explorePersonalized == personalized) return;
                              setState(
                                  () => _explorePersonalized = personalized);
                              _exploreActions.selectExplore(personalized);
                            },
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _explorePersonalized == personalized
                                        ? colorScheme.primary
                                        : colorScheme.outlineVariant,
                                    width: _explorePersonalized == personalized
                                        ? 3
                                        : 1,
                                  ),
                                ),
                              ),
                              child: Text(
                                personalized ? '探索' : '当前趋势',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: context.adjustWeight(
                                    _explorePersonalized == personalized
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : null,
      actions: [
        if (controller.loggedIn && _tab == 0)
          IconButton(
              tooltip: '发布帖子',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ComposePage()))),
      ],
    );
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    final pageTopChromeHeight = statusBarHeight + appBar.preferredSize.height;
    final topChromeHeight = _tab == 2 ? statusBarHeight : pageTopChromeHeight;
    final loginPrompt = Center(
        child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.forum_outlined, size: 72, color: colorScheme.primary),
              const SizedBox(height: 24),
              Text('ReviewX', style: materialTheme.textTheme.headlineLarge),
              const SizedBox(height: 12),
              const Text('登录 X，阅读你的关注时间线', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                  onPressed: _login,
                  icon: const Icon(Icons.login),
                  label: const Text('登录 X')),
            ])));
    final pages = <Widget>[
      controller.loggedIn
          ? TabBarView(
              controller: _homeTimelineController,
              children: [
                TimelinePage(
                    cacheKey: 'for_you',
                    topPadding: controller.expired ? 0 : pageTopChromeHeight,
                    actions: _forYouActions,
                    load: (cursor, {refresh, seenIds}) =>
                        controller.adapter.forYou(
                          cursor: cursor,
                          refresh: refresh,
                          seenTweetIds: seenIds,
                        )),
                _visitedHomeTimelineTabs.contains(1)
                    ? TimelinePage(
                        cacheKey: 'following',
                        topPadding:
                            controller.expired ? 0 : pageTopChromeHeight,
                        actions: _followingActions,
                        load: (cursor, {refresh, seenIds}) =>
                            controller.adapter.following(
                              cursor: cursor,
                              refresh: refresh,
                              seenTweetIds: seenIds,
                            ))
                    : const SizedBox.shrink(),
              ],
            )
          : loginPrompt,
      controller.loggedIn
          ? _visited.contains(1)
              ? SearchPage(
                  showExplore: true,
                  searchController: _exploreSearchController,
                  searchFocusNode: _exploreSearchFocus,
                  topChromeHeight: controller.expired ? 0 : pageTopChromeHeight,
                  personalized: _explorePersonalized,
                  actions: _exploreActions,
                )
              : const SizedBox.shrink()
          : loginPrompt,
      SettingsPane(topChromeHeight: controller.expired ? 0 : statusBarHeight),
    ];
    return GlassPage(
      enableBackgroundSampling: useLiquidGlassNavigation,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const AppDrawer(),
        extendBody: theme.useFloatingNavBar,
        extendBodyBehindAppBar: _tab != 2,
        appBar: _tab == 2
            ? null
            : PreferredSize(
                preferredSize: appBar.preferredSize,
                child: _tab == 0
                    ? GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _onTopBarTap,
                        child: appBar)
                    : appBar),
        body: GlassBackgroundSource(
          enabled: useLiquidGlassNavigation,
          child: Column(children: [
            if (controller.expired)
              Padding(
                padding: EdgeInsets.only(top: topChromeHeight),
                child: MaterialBanner(
                    content: const Text('X 会话已过期，请重新登录'),
                    actions: [
                      TextButton(onPressed: _login, child: const Text('重新登录'))
                    ]),
              ),
            Expanded(child: _buildTabContent(pages)),
          ]),
        ),
        bottomNavigationBar: theme.useFloatingNavBar
            ? useLiquidGlassNavigation
                ? GlassAdaptiveScope(
                    child: _LiquidGlassNavigationBar(
                      selectedIndex: _tab,
                      onSelected: _onNavigationItemSelected,
                      width: floatingNavWidth,
                    ),
                  )
                : SafeArea(
                    child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: 1,
                        child: Padding(
                            padding: EdgeInsets.only(
                                bottom: bottomPadding > 0 ? 6 : 14),
                            child: floatingCapsuleBar)))
            : standardNavBar,
      ),
    );
  }

  Widget _buildCapsuleItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _tab == index;
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
          child: Column(
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
        ),
      ),
    );
  }
}

class _LiquidGlassNavigationBar extends StatefulWidget {
  const _LiquidGlassNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.width,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double width;

  @override
  State<_LiquidGlassNavigationBar> createState() =>
      _LiquidGlassNavigationBarState();
}

class _LiquidGlassNavigationBarState extends State<_LiquidGlassNavigationBar> {
  static const _longPressThreshold = Duration(milliseconds: 500);
  static const _flickVelocityThreshold = 1000.0;

  int? _activePointer;
  VelocityTracker? _velocityTracker;
  Duration? _pointerDownAt;
  Offset? _pointerDownPosition;
  int _selectedIndexAtPointerDown = 0;
  int? _pendingIndex;
  bool _movedBeyondSlop = false;
  bool _draggedHorizontally = false;
  bool _cancelled = false;
  int _gestureId = 0;

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _pointerDownAt = event.timeStamp;
    _pointerDownPosition = event.position;
    _selectedIndexAtPointerDown = widget.selectedIndex;
    _pendingIndex = null;
    _movedBeyondSlop = false;
    _draggedHorizontally = false;
    _cancelled = false;
    _gestureId++;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final delta = event.position - _pointerDownPosition!;
    if (delta.distance > kTouchSlop) {
      _movedBeyondSlop = true;
      if (delta.dx.abs() > delta.dy.abs()) _draggedHorizontally = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) => _finishPointer(
        event.pointer,
        event.timeStamp,
        horizontalVelocity:
            _velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0,
      );

  void _onPointerCancel(PointerCancelEvent event) =>
      _finishPointer(event.pointer, event.timeStamp, cancelled: true);

  void _finishPointer(
    int pointer,
    Duration releasedAt, {
    bool cancelled = false,
    double horizontalVelocity = 0,
  }) {
    if (pointer != _activePointer) return;
    _cancelled |= cancelled;
    final gestureId = _gestureId;
    scheduleMicrotask(() {
      if (!mounted || gestureId != _gestureId) return;

      final target = _pendingIndex;
      final wasLongPress = releasedAt - _pointerDownAt! >= _longPressThreshold;
      final wasDrag = _draggedHorizontally;
      final movedVertically = _movedBeyondSlop && !wasDrag;
      final wasCancelled = _cancelled;
      final startingIndex = _selectedIndexAtPointerDown;

      _activePointer = null;
      _velocityTracker = null;
      _pointerDownAt = null;
      _pointerDownPosition = null;
      _pendingIndex = null;
      _movedBeyondSlop = false;
      _draggedHorizontally = false;
      _cancelled = false;

      if (wasCancelled || movedVertically || target == null) return;

      final isFastFlick =
          wasDrag && horizontalVelocity.abs() >= _flickVelocityThreshold;
      final selectedTarget = isFastFlick
          ? target.clamp(startingIndex - 1, startingIndex + 1).toInt()
          : target;
      if ((wasDrag || wasLongPress) && selectedTarget == startingIndex) return;
      _select(selectedTarget);
    });
  }

  void _onTabSelected(int index) {
    if (_activePointer != null) {
      _pendingIndex = index;
    } else {
      _select(index);
    }
  }

  void _select(int index) {
    HapticFeedbackUtil.light();
    widget.onSelected(index);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        minimum: const EdgeInsets.only(bottom: 21),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: widget.width,
            height: 56,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: GlassTabBar.bottom(
                tabs: const [
                  GlassTab(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: '首页',
                  ),
                  GlassTab(
                    icon: Icon(Icons.explore_outlined),
                    activeIcon: Icon(Icons.explore),
                    label: '探索',
                  ),
                  GlassTab(
                    icon: Icon(Icons.settings_outlined),
                    activeIcon: Icon(Icons.settings_rounded),
                    label: '设置',
                  ),
                ],
                selectedIndex: widget.selectedIndex,
                onTabSelected: _onTabSelected,
                barHeight: 56,
                horizontalPadding: 0,
                verticalPadding: 0,
                barBorderRadius: 9999,
                indicatorBorderRadius: 9999,
                settings: const LiquidGlassSettings(
                  glassColor: Color(0x66000000),
                  bodyMode: GlassBodyMode.clear,
                  thickness: 10,
                  blur: 2,
                  lightIntensity: 0.25,
                  ambientStrength: 0,
                  refractiveIndex: 1.19,
                  chromaticAberration: 0.008,
                  shadowElevation: 0,
                ),
                indicatorSettings: const LiquidGlassSettings(
                  refractiveIndex: 1.18,
                  chromaticAberration: 0.025,
                ),
                quality: GlassQuality.premium,
                backgroundQuality: GlassQuality.premium,
                indicatorColor: const Color(0x66000000),
                interactionGlowColor: const Color(0x20FFFFFF),
                indicatorPinchStrength: 0.7,
                innerBlur: 6,
                pressScale: 1.06,
                selectedIconColor: Colors.white,
                selectedLabelColor: Colors.white,
                unselectedIconColor: Colors.white,
                unselectedLabelColor: Colors.white,
              ),
            ),
          ),
        ),
      );
}
