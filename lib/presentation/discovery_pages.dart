import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/models/social_models.dart';
import '../twitter/models/content_models.dart';
import '../core/widgets/cached_network_image.dart';
import 'timeline_page.dart';
import 'post_card.dart';
import 'request_status.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage(
      {super.key,
      this.initialQuery = '',
      this.showExplore = false,
      this.actions});
  final String initialQuery;
  final bool showExplore;
  final ScrollPageActions? actions;
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery;
  String _product = 'Top';
  int _revision = 0;
  List<TrendingTopic> _trends = const [];
  String? _trendsError;
  bool _trendsLoading = false;
  bool _trendsLoaded = false;
  bool _personalized = true;
  int _guideRequest = 0;
  List<SocialUser> _recommendations = const [];
  String? _recommendationsError;
  bool _recommendationsLoading = false;
  final ScrollController _exploreScrollController = ScrollController();
  final ScrollPageActions _searchTimelineActions = ScrollPageActions();

  @override
  void initState() {
    super.initState();
    widget.actions?.attach(this,
        onSingleTap: _handleBottomBarSingleTap,
        onDoubleTap: _handleBottomBarDoubleTap,
        onTopBarDoubleTap: _handleTopBarDoubleTap);
    if (widget.showExplore && widget.initialQuery.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadTrends();
        _loadRecommendations();
      });
    }
  }

  void _scrollExploreToTop() {
    if (!_exploreScrollController.hasClients ||
        _exploreScrollController.offset <= 0) {
      return;
    }
    _exploreScrollController.animateTo(0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic);
  }

  void _handleBottomBarSingleTap() {
    if (!widget.showExplore) return;
    if (_query.isEmpty) {
      _scrollExploreToTop();
    } else {
      _searchTimelineActions.handleSingleTap();
    }
  }

  void _handleBottomBarDoubleTap() {
    if (!widget.showExplore) return;
    if (_query.isEmpty) {
      _scrollExploreToTop();
      unawaited(_refreshExplore());
    } else {
      _searchTimelineActions.handleDoubleTap();
    }
  }

  void _handleTopBarDoubleTap() {
    if (!widget.showExplore) return;
    if (_query.isNotEmpty) {
      _searchTimelineActions.handleTopBarDoubleTap();
    } else if (_exploreScrollController.hasClients &&
        _exploreScrollController.offset > 50) {
      _scrollExploreToTop();
    } else {
      unawaited(_refreshExplore());
    }
  }

  Future<void> _refreshExplore() async {
    await Future.wait([
      _loadTrends(force: true),
      if (_personalized) _loadRecommendations(),
    ]);
  }

  Future<void> _loadTrends({bool force = false}) async {
    if (_trendsLoading || (_trendsLoaded && !force)) return;
    final controller = ref.read(appControllerProvider);
    final epoch = controller.epoch;
    final request = ++_guideRequest;
    setState(() {
      _trendsLoading = true;
      _trendsError = null;
    });
    try {
      final trends =
          await controller.adapter.trends(personalized: _personalized);
      if (!mounted || epoch != controller.epoch || request != _guideRequest) {
        return;
      }
      setState(() {
        _trends = trends;
        _trendsLoaded = true;
      });
    } catch (error) {
      controller.report(error);
      if (mounted && epoch == controller.epoch && request == _guideRequest) {
        setState(() => _trendsError = '$error');
      }
    } finally {
      if (mounted && request == _guideRequest) {
        setState(() => _trendsLoading = false);
      }
    }
  }

  Future<void> _loadRecommendations() async {
    if (_recommendationsLoading) return;
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    setState(() {
      _recommendationsLoading = true;
      _recommendationsError = null;
    });
    try {
      final users = await controller.adapter.recommendedUsers();
      if (mounted && epoch == controller.epoch) {
        setState(() => _recommendations = users);
      }
    } catch (error) {
      controller.report(error);
      if (mounted && epoch == controller.epoch) {
        setState(() => _recommendationsError = '$error');
      }
    } finally {
      if (mounted) setState(() => _recommendationsLoading = false);
    }
  }

  void _selectExplore(bool personalized) {
    if (_personalized == personalized) return;
    setState(() {
      _personalized = personalized;
      _trends = const [];
      _trendsLoaded = false;
      _trendsLoading = false;
      _trendsError = null;
      _guideRequest++;
    });
    _loadTrends();
  }

  void _searchTrend(TrendingTopic trend) {
    _text.text = trend.name;
    setState(() {
      _query = trend.name;
      _product = 'Top';
      _revision++;
    });
  }

  @override
  void dispose() {
    widget.actions?.detach(this);
    _exploreScrollController.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adapter = ref.read(appControllerProvider).adapter;
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
              controller: _text,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => setState(() {
                    _query = value.trim();
                    _revision++;
                  }),
              decoration: InputDecoration(
                  hintText: '搜索 X',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => setState(() {
                            _query = _text.text.trim();
                            _revision++;
                          })),
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(32),
                      borderSide: BorderSide.none)))),
      if (widget.showExplore && _query.isEmpty)
        Row(children: [
          for (final personalized in [true, false])
            Expanded(
                child: InkWell(
              onTap: () => _selectExplore(personalized),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: _personalized == personalized
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: _personalized == personalized ? 3 : 1))),
                child: Text(personalized ? '探索' : '当前趋势',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: _personalized == personalized
                            ? FontWeight.bold
                            : FontWeight.normal)),
              ),
            )),
        ]),
      if (!widget.showExplore || _query.isNotEmpty)
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final entry in const {
                'Top': '热门',
                'Latest': '最新',
                'People': '用户',
                'Photos': '图片',
                'Videos': '视频'
              }.entries)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                        label: Text(entry.value),
                        selected: _product == entry.key,
                        onSelected: (_) => setState(() {
                              _product = entry.key;
                              _revision++;
                            })))
            ])),
      Expanded(
          child: _query.isEmpty
              ? widget.showExplore
                  ? _buildTrends()
                  : const Center(child: Text('输入关键词、@账号或 #话题'))
              : _product == 'People'
                  ? UserList(
                      key: ValueKey('$_query/$_revision'),
                      load: (cursor) =>
                          adapter.searchUsers(_query, cursor: cursor))
                  : TimelinePage(
                      key: ValueKey('$_query/$_product/$_revision'),
                      actions:
                          widget.showExplore ? _searchTimelineActions : null,
                      load: (cursor) => adapter.search(_query,
                          product: _product, cursor: cursor)))
    ]);
  }

  Widget _buildTrends() => Column(children: [
        RequestStatus(
          loading: _trendsLoading || (_personalized && _recommendationsLoading),
          error: _trendsError ?? (_personalized ? _recommendationsError : null),
          onRetry: () => _refreshExplore(),
        ),
        Expanded(
            child: RefreshIndicator(
          onRefresh: () async {
            await _refreshExplore();
          },
          child: ListView(
            controller: _exploreScrollController,
            padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(_personalized ? '为你推荐的趋势' : '当前趋势',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
              ),
              if (!_trendsLoading && _trendsError == null && _trends.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('当前没有可显示的趋势')),
                )
              else
                for (var index = 0; index < _trends.length; index++)
                  _TrendTile(
                    trend: _trends[index],
                    onTap: () => _searchTrend(_trends[index]),
                  ),
              if (_personalized) ...[
                const Divider(),
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('推荐关注',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold))),
                for (final user in _recommendations)
                  _RecommendedUserTile(key: ValueKey(user.id), user: user),
                if (!_recommendationsLoading &&
                    _recommendationsError == null &&
                    _recommendations.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16), child: Text('X 暂未返回推荐用户')),
              ],
            ],
          ),
        ))
      ]);
}

class _TrendTile extends StatelessWidget {
  const _TrendTile({required this.trend, required this.onTap});
  final TrendingTopic trend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trend.description.isEmpty ? '趋势' : trend.description,
                style: TextStyle(color: secondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text(trend.name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            if (trend.metaDescription.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(trend.metaDescription, style: TextStyle(color: secondary)),
            ],
          ])),
    );
  }
}

class _RecommendedUserTile extends ConsumerStatefulWidget {
  const _RecommendedUserTile({super.key, required this.user});
  final SocialUser user;
  @override
  ConsumerState<_RecommendedUserTile> createState() =>
      _RecommendedUserTileState();
}

class _RecommendedUserTileState extends ConsumerState<_RecommendedUserTile> {
  SocialUser? _updated;
  bool _busy = false, _uncertain = false;
  @override
  void didUpdateWidget(covariant _RecommendedUserTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.user, widget.user) && !_busy) {
      _updated = null;
      _uncertain = false;
    }
  }

  Future<void> _follow() async {
    if (_busy || _uncertain) return;
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    setState(() => _busy = true);
    try {
      final updated = await controller.adapter.follow(widget.user.id, true);
      if (mounted && epoch == controller.epoch) {
        setState(() => _updated = updated);
      }
    } catch (error) {
      controller.report(error);
      if (mounted && epoch == controller.epoch) {
        // The adapter confirms the returned relationship; never retry an uncertain write automatically.
        setState(() => _uncertain = true);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _updated ?? widget.user;
    return ListTile(
      leading: ClipOval(
          child: user.avatar.isEmpty
              ? const SizedBox(width: 40, height: 40, child: Icon(Icons.person))
              : CachedNetworkImage(user.avatar,
                  width: 40, height: 40, fit: BoxFit.cover)),
      title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('@${user.handle}\n${user.description}',
          maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: FilledButton(
          onPressed:
              _busy || _uncertain || user.isFollowing || user.followRequested
                  ? null
                  : _follow,
          child: Text(_busy
              ? '提交中'
              : _uncertain
                  ? '待核对'
                  : user.followRequested
                      ? '已请求'
                      : user.isFollowing
                          ? '已关注'
                          : '关注')),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => ProfilePage(user: user))),
    );
  }
}

class UserList extends ConsumerStatefulWidget {
  const UserList({super.key, required this.load});
  final Future<UserPage> Function(String? cursor) load;
  @override
  ConsumerState<UserList> createState() => _UserListState();
}

class _UserListState extends ConsumerState<UserList> {
  List<SocialUser> _users = [];
  String? _cursor, _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _fetch(true);
  }

  Future<void> _fetch(bool refresh) async {
    if (_loading) return;
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.load(refresh ? null : _cursor);
      if (!mounted || epoch != controller.epoch) return;
      setState(() {
        final users = {
          for (final user in refresh ? <SocialUser>[] : _users) user.id: user,
          for (final user in page.users) user.id: user
        };
        if (users.isNotEmpty || _users.isEmpty) _users = users.values.toList();
        _cursor = !refresh && page.cursor == _cursor ? null : page.cursor;
      });
    } catch (error) {
      controller.report(error);
      if (mounted && epoch == controller.epoch) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: () => _fetch(true),
      child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _users.length + 1,
          itemBuilder: (context, index) {
            if (index == _users.length) {
              return Padding(
                  padding: const EdgeInsets.all(20),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(children: [
                          if (_error != null) Text(_error!),
                          if (_cursor != null || _error != null)
                            TextButton(
                                onPressed: () => _fetch(_users.isEmpty),
                                child: Text(_error == null ? '加载更多' : '重试')),
                          if (_users.isEmpty && _error == null)
                            const Text('没有用户')
                        ]));
            }
            final user = _users[index];
            return ListTile(
                leading: ClipOval(
                    child: user.avatar.isEmpty
                        ? const Icon(Icons.person)
                        : CachedNetworkImage(user.avatar,
                            width: 42, height: 42, fit: BoxFit.cover)),
                title: Text(user.name),
                subtitle: Text('@${user.handle}\n${user.description}',
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ProfilePage(user: user))));
          }));
}

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  List<SocialNotification> _items = [];
  String? _cursor, _top, _error;
  bool _loading = false, _marking = false, _marked = false, _uncertain = false;
  @override
  void initState() {
    super.initState();
    _fetch(true);
  }

  Future<void> _fetch(bool refresh) async {
    if (_loading) return;
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await controller.adapter
          .notifications(cursor: refresh ? null : _cursor);
      if (!mounted || epoch != controller.epoch) return;
      controller.ingest(page.notifications.expand((n) => n.posts).toList());
      setState(() {
        final values = {
          for (final n in refresh ? <SocialNotification>[] : _items) n.id: n,
          for (final n in page.notifications) n.id: n
        };
        if (values.isNotEmpty || _items.isEmpty) {
          _items = values.values.toList();
        }
        _cursor = !refresh && page.cursor == _cursor ? null : page.cursor;
        if (refresh) {
          _top = page.topCursor;
          _marked = false;
          _uncertain = false;
        }
      });
    } catch (error) {
      controller.report(error);
      if (mounted && epoch == controller.epoch) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead() async {
    if (_top == null || _marking || _uncertain) return;
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    setState(() => _marking = true);
    try {
      await controller.adapter.markNotificationsRead(_top!);
      if (mounted && epoch == controller.epoch) setState(() => _marked = true);
    } catch (error) {
      controller.report(error);
      if (mounted && epoch == controller.epoch) {
        setState(() {
          _error = '$error';
          _uncertain = true;
        });
      }
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: () => _fetch(true),
      child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _items.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return ListTile(
                  title: const Text('X 通知'),
                  subtitle: _uncertain ? const Text('已读结果待核对，请在 X 查看') : null,
                  trailing: TextButton(
                      onPressed:
                          _top == null || _marking || _marked || _uncertain
                              ? null
                              : _markRead,
                      child: Text(_marked
                          ? '已在 X 标记已读'
                          : _marking
                              ? '提交中…'
                              : '标记已读')));
            }
            if (index == _items.length + 1) {
              return Padding(
                  padding: const EdgeInsets.all(20),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(children: [
                          if (_error != null) Text(_error!),
                          if (_cursor != null || _error != null)
                            TextButton(
                                onPressed: () => _fetch(_items.isEmpty),
                                child: Text(_error == null ? '加载更多' : '重新加载')),
                          if (_items.isEmpty && _error == null)
                            const Text('暂无通知')
                        ]));
            }
            final n = _items[index - 1];
            return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(children: [
                  ListTile(
                      leading: Icon(n.icon.contains('heart')
                          ? Icons.favorite
                          : n.icon.contains('retweet')
                              ? Icons.repeat
                              : Icons.notifications_outlined),
                      title: Text(n.message.isEmpty ? 'X 通知' : n.message),
                      subtitle: n.createdAt == null
                          ? null
                          : Text('${n.createdAt!.toLocal()}'.split('.').first),
                      onTap: n.posts.isNotEmpty
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      PostDetailPage(post: n.posts.first)))
                          : n.actors.isNotEmpty
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          ProfilePage(user: n.actors.first)))
                              : safeLink(n.url) &&
                                      const ['x.com', 'twitter.com']
                                          .contains(Uri.parse(n.url).host)
                                  ? () => launchUrl(Uri.parse(n.url),
                                      mode: LaunchMode.externalApplication)
                                  : null),
                  if (n.actors.isNotEmpty)
                    Wrap(children: [
                      for (final user in n.actors.take(8))
                        TextButton(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ProfilePage(user: user))),
                            child: Text('@${user.handle}'))
                    ]),
                  for (final post in n.posts.take(3)) PostCard(post: post)
                ]));
          }));
}
