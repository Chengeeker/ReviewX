import 'dart:async';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/widgets/cached_network_image.dart';
import '../core/widgets/frosted_app_bar.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/storage/reading_settings.dart';
import '../core/storage/storage_service.dart';
import '../twitter/api/twitter_client.dart';
import '../twitter/repositories/twitter_adapter.dart';
import '../twitter/models/content_models.dart';
import 'discovery_pages.dart';
import 'media_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/cache/local_x_cache.dart';
import '../twitter/models/social_models.dart';
import 'post_card.dart';
import 'request_status.dart';

typedef PageLoader = Future<PostPage> Function(String? cursor);

bool _continuesConversation(SocialPost parent, SocialPost reply) =>
    parent.repostedBy == null &&
    reply.repostedBy == null &&
    reply.replyToId == parent.id &&
    (parent.conversationId == null ||
        reply.conversationId == null ||
        parent.conversationId == reply.conversationId);

/// Lets the selected bottom tab control the scrollable that currently owns
/// the visible feed without coupling the app shell to a private State class.
class ScrollPageActions {
  Object? _owner;
  VoidCallback? _singleTap, _doubleTap, _topBarDoubleTap;
  ValueChanged<String>? _searchSubmitted;
  ValueChanged<bool>? _exploreSelected;

  void attach(Object owner,
      {required VoidCallback onSingleTap,
      required VoidCallback onDoubleTap,
      required VoidCallback onTopBarDoubleTap,
      ValueChanged<String>? onSearchSubmitted,
      ValueChanged<bool>? onExploreSelected}) {
    _owner = owner;
    _singleTap = onSingleTap;
    _doubleTap = onDoubleTap;
    _topBarDoubleTap = onTopBarDoubleTap;
    _searchSubmitted = onSearchSubmitted;
    _exploreSelected = onExploreSelected;
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _singleTap = null;
    _doubleTap = null;
    _topBarDoubleTap = null;
    _searchSubmitted = null;
    _exploreSelected = null;
  }

  void handleSingleTap() => _singleTap?.call();
  void handleDoubleTap() => _doubleTap?.call();
  void handleTopBarDoubleTap() => _topBarDoubleTap?.call();
  void submitSearch(String query) => _searchSubmitted?.call(query);
  void selectExplore(bool personalized) => _exploreSelected?.call(personalized);
}

class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage(
      {super.key,
      required this.load,
      this.header,
      this.initial = const [],
      this.initialCursor,
      this.loadOnInit = true,
      this.cacheKey,
      this.conversationRoot,
      this.topPadding = 0,
      this.actions});
  final PageLoader load;
  final Widget? header;
  final List<SocialPost> initial;
  final String? initialCursor;
  final bool loadOnInit;
  final String? cacheKey;
  final SocialPost? conversationRoot;
  final double topPadding;
  final ScrollPageActions? actions;
  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  late List<SocialPost> _posts = widget.initial;
  late String? _cursor = widget.initialCursor;
  String? _error;
  bool _loading = false;
  bool _refreshing = false;
  int _request = 0;
  late final ScrollController _scrollController = ScrollController();
  double _savedOffset = 0;
  @override
  void initState() {
    super.initState();
    final cacheKey = widget.cacheKey;
    final controller = ref.read(appControllerProvider);
    final accountId = controller.client.session?.userId;
    if (cacheKey != null && accountId != null) {
      _posts = ref.read(localXCacheProvider).readTimeline(accountId, cacheKey);
    }
    widget.actions?.attach(this,
        onSingleTap: _handleBottomSingleTap,
        onDoubleTap: _handleBottomDoubleTap,
        onTopBarDoubleTap: _handleTopBarDoubleTap);
    if (widget.loadOnInit) _fetch(refresh: true);
  }

  void _animateToTop() {
    if (!_scrollController.hasClients || _scrollController.offset <= 0) return;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic);
  }

  void _handleBottomSingleTap() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.offset > 50) {
      _savedOffset = _scrollController.offset;
      _animateToTop();
    } else if (_savedOffset > 50) {
      final target = _savedOffset;
      _savedOffset = 0;
      _scrollController.animateTo(target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic);
    } else {
      _animateToTop();
    }
  }

  void _handleBottomDoubleTap() {
    _animateToTop();
    unawaited(_fetch(refresh: true));
  }

  void _handleTopBarDoubleTap() {
    if (_scrollController.hasClients && _scrollController.offset > 50) {
      _savedOffset = _scrollController.offset;
      _animateToTop();
    } else {
      unawaited(_fetch(refresh: true));
    }
  }

  Future<void> _fetch({bool refresh = false}) async {
    if ((_loading && !refresh) || (refresh && _refreshing)) return;
    if (refresh) _refreshing = true;
    final generation = ++_request;
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    final accountId = controller.client.session?.userId;
    final oldCursor = _cursor;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.load(refresh ? null : _cursor);
      if (!mounted || generation != _request || controller.epoch != epoch) {
        return;
      }
      final cacheKey = widget.cacheKey;
      if (refresh &&
          page.posts.isNotEmpty &&
          cacheKey != null &&
          accountId != null &&
          controller.client.session?.userId == accountId) {
        unawaited(ref
            .read(localXCacheProvider)
            .writeTimeline(accountId, cacheKey, page.posts));
      }
      controller.ingest(page.posts);
      final incoming = <String, SocialPost>{
        for (final post in refresh ? <SocialPost>[] : _posts) post.id: post
      };
      for (final post in page.posts) {
        incoming[post.id] = post;
      }
      setState(() {
        // Empty refresh preserves existing rows, but not a stale pagination cursor.
        if (incoming.isNotEmpty || _posts.isEmpty) {
          _posts = incoming.values.toList();
        }
        _cursor = !refresh && page.cursor == oldCursor ? null : page.cursor;
      });
    } catch (error) {
      controller.report(error);
      if (mounted && generation == _request && controller.epoch == epoch) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (refresh) _refreshing = false;
      if (mounted && generation == _request) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _request++;
    widget.actions?.detach(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final known = <String, SocialPost>{
      if (widget.conversationRoot != null)
        widget.conversationRoot!.id: widget.conversationRoot!,
      if (widget.conversationRoot != null)
        for (final post in _posts) post.id: post,
    };
    return RefreshIndicator(
        onRefresh: () => _fetch(refresh: true),
        child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
                top: widget.topPadding,
                bottom: MediaQuery.paddingOf(context).bottom > 24
                    ? MediaQuery.paddingOf(context).bottom
                    : 24),
            itemCount: _posts.length + 3,
            itemBuilder: (context, index) {
              if (index == 0) {
                return RequestStatus(
                    loading: _loading,
                    error: _error,
                    onRetry: () => _fetch(refresh: true));
              }
              if (index == 1) {
                return widget.header ?? const SizedBox.shrink();
              }
              if (index <= _posts.length + 1) {
                final post = _posts[index - 2];
                final connectedAbove = widget.conversationRoot == null &&
                    index > 2 &&
                    _continuesConversation(_posts[index - 3], post);
                final connectedBelow = widget.conversationRoot == null &&
                    index < _posts.length + 1 &&
                    _continuesConversation(post, _posts[index - 1]);
                final parent = widget.conversationRoot == null
                    ? null
                    : known[post.replyToId];
                var depth = 0;
                var ancestor = parent;
                final seen = <String>{post.id};
                while (ancestor != null &&
                    ancestor.id != widget.conversationRoot?.id &&
                    depth < 2 &&
                    seen.add(ancestor.id)) {
                  depth++;
                  ancestor = known[ancestor.replyToId];
                }
                return Padding(
                    key: ValueKey(post.id),
                    padding: EdgeInsets.only(left: depth * 12.0),
                    child: PostCard(
                        post: post,
                        connectedAbove: connectedAbove,
                        connectedBelow: connectedBelow,
                        replyParent: parent,
                        showReplyParentPreview:
                            parent?.id != widget.conversationRoot?.id));
              }
              return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    if (!_loading && _error == null && _cursor != null)
                      FilledButton.tonal(
                          onPressed: _fetch, child: const Text('加载更多')),
                    if (!_loading && _error == null && _cursor == null)
                      Text(_posts.isEmpty ? '暂无帖子，下拉刷新' : '没有更多帖子')
                  ]));
            }));
  }
}

class BookmarksPage extends ConsumerWidget {
  const BookmarksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final appBar = buildFrostedAppBar(context, title: const Text('书签'));
    final topChromeHeight =
        MediaQuery.paddingOf(context).top + appBar.preferredSize.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: TimelinePage(
        topPadding: topChromeHeight,
        load: (cursor) => controller.adapter.bookmarks(cursor: cursor),
      ),
    );
  }
}

class PostDetailPage extends ConsumerStatefulWidget {
  const PostDetailPage({Key? key, required SocialPost post})
      : this._(post: post, key: key);
  const PostDetailPage.fromId({Key? key, required String postId})
      : this._(postId: postId, key: key);
  const PostDetailPage._({super.key, this.post, this.postId});

  final SocialPost? post;
  final String? postId;
  @override
  ConsumerState<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends ConsumerState<PostDetailPage> {
  ReplySort _sort = ReplySort.relevance;
  int _sortGeneration = 0;
  SocialPost? _replyParent;
  SocialPost? _post;
  List<SocialPost> _initialReplies = const [];
  String? _initialCursor, _loadError;
  ReplySort? _initialSort;
  String? _conversationId;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    if (_post == null) {
      unawaited(_loadPost());
    } else {
      _recordHistory(_post!);
    }
  }

  void _recordHistory(SocialPost post) {
    final account = ref.read(appControllerProvider).client.session?.userId;
    if (account != null && ref.read(readingProvider)['saveHistory'] == true) {
      BrowsingHistory(ref.read(storageServiceProvider)).add(account,
          id: post.id,
          url: post.url,
          title: post.text,
          author: post.author.name);
    }
  }

  Future<void> _loadPost() async {
    final id = widget.postId;
    if (id == null || !RegExp(r'^\d{1,30}$').hasMatch(id)) {
      setState(() => _loadError = '帖子链接无效');
      return;
    }
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch,
        sort = _sort,
        generation = _sortGeneration;
    try {
      final page = await controller.adapter.detail(id, sort: sort);
      if (!mounted ||
          epoch != controller.epoch ||
          generation != _sortGeneration ||
          sort != _sort) {
        return;
      }
      controller.ingest(page.posts);
      final post = page.posts.where((item) => item.id == id).firstOrNull;
      if (post == null) throw const TwitterFailure('X 未返回链接对应的帖子');
      final rootIndex = page.posts.indexWhere((item) => item.id == id);
      final replies = page.posts.skip(rootIndex + 1).where((item) {
        return (post.conversationId == null ||
                item.conversationId == null ||
                item.conversationId == post.conversationId) &&
            item.id != post.id;
      }).toList();
      final parent =
          page.posts.where((item) => item.id == post.replyToId).firstOrNull;
      setState(() {
        _post = post;
        _replyParent = parent;
        _initialReplies = replies;
        _initialCursor = page.cursor;
        _initialSort = sort;
        _conversationId = post.conversationId;
        _loadError = null;
      });
      _recordHistory(post);
    } catch (error) {
      controller.report(error);
      if (mounted &&
          epoch == controller.epoch &&
          generation == _sortGeneration) {
        setState(() => _loadError = '$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final controller = ref.read(appControllerProvider);
    if (post == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('帖子详情')),
          body: Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                          onPressed: _loadPost, child: const Text('重试'))
                    ])));
    }
    final useInitialPage = _initialSort == _sort;
    return Scaffold(
        appBar: AppBar(title: const Text('帖子详情')),
        body: TimelinePage(
            key: ValueKey('${post.id}/${_sort.name}/${controller.epoch}'),
            conversationRoot: post,
            initial: useInitialPage ? _initialReplies : const [],
            initialCursor: useInitialPage ? _initialCursor : null,
            loadOnInit: !useInitialPage,
            header: Column(children: [
              PostCard(post: post, detail: true, replyParent: _replyParent),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(children: [
                  const Expanded(child: Text('回复')),
                  PopupMenuButton<ReplySort>(
                    tooltip: '回复排序',
                    initialValue: _sort,
                    onSelected: (value) {
                      if (value != _sort) {
                        setState(() {
                          _sort = value;
                          _sortGeneration++;
                        });
                      }
                    },
                    itemBuilder: (_) => [
                      for (final sort in ReplySort.values)
                        CheckedPopupMenuItem(
                            value: sort,
                            checked: sort == _sort,
                            child: Text(sort.label))
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_sort.label),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more, size: 20),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
            load: (cursor) async {
              final sort = _sort,
                  epoch = controller.epoch,
                  generation = _sortGeneration;
              final page = await controller.adapter
                  .detail(post.id, cursor: cursor, sort: sort);
              if (!mounted ||
                  generation != _sortGeneration ||
                  sort != _sort ||
                  epoch != controller.epoch) {
                return const PostPage([], null);
              }
              controller.ingest(page.posts);
              final focal =
                  page.posts.where((item) => item.id == post.id).firstOrNull;
              final parent = page.posts
                  .where(
                      (item) => item.id == (focal?.replyToId ?? post.replyToId))
                  .firstOrNull;
              if (parent != null) setState(() => _replyParent = parent);
              // Ancestors belong in the focal post's context, not the reply list.
              final focalIndex = cursor == null
                  ? page.posts.indexWhere((item) => item.id == post.id)
                  : -1;
              final replies =
                  focalIndex < 0 ? page.posts : page.posts.skip(focalIndex + 1);
              final conversationId = focal?.conversationId ??
                  _conversationId ??
                  post.conversationId;
              _conversationId = conversationId;
              return PostPage(
                  replies
                      .where((item) =>
                          item.id != post.id &&
                          (conversationId == null ||
                              item.conversationId == null ||
                              item.conversationId == conversationId))
                      .toList(),
                  page.cursor);
            }));
  }
}

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, required this.user, this.refreshOnOpen = true});
  final SocialUser user;
  final bool refreshOnOpen;
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final Object _profileBannerHeroScope = Object();
  final Object _profileAvatarHeroScope = Object();
  late SocialUser _user = widget.user;
  String? _profileError;
  int _category = 0;
  String _tweetMode = 'UserTweets', _mediaMode = 'UserPhotoTimeline';
  String get _operation => [
        _tweetMode,
        'UserTweetsAndReplies',
        'UserRepostsTimeline',
        _mediaMode,
        'UserArticlesTweets',
        'Likes'
      ][_category];
  bool get _isMe =>
      _user.id == ref.read(appControllerProvider).client.session?.userId;
  bool _following = false, _followUncertain = false;
  @override
  void initState() {
    super.initState();
    if (widget.refreshOnOpen) _loadProfile();
  }

  Future<void> _loadProfile() async {
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    try {
      final user = await controller.adapter.user(_user.id);
      if (mounted && controller.epoch == epoch) {
        setState(() {
          _user = user.preservingCounts(_user);
          _profileError = null;
          _followUncertain = false;
        });
      }
    } catch (error) {
      controller.report(error);
      if (mounted && controller.epoch == epoch) {
        setState(() => _profileError = error.toString());
      }
    }
  }

  Future<void> _follow() async {
    if (_following || _followUncertain) return;
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    setState(() => _following = true);
    try {
      final updated =
          await controller.adapter.follow(_user.id, !_user.isFollowing);
      if (mounted && controller.epoch == epoch) {
        setState(() => _user = updated.preservingCounts(_user));
      }
    } catch (error) {
      controller.report(error);
      if (mounted && controller.epoch == epoch) {
        setState(() {
          _profileError = '$error';
          _followUncertain = error is TwitterFailure && error.uncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  void _list(bool followers) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Scaffold(
              appBar: AppBar(title: Text(followers ? '关注者' : '关注')),
              body: UserList(
                  load: (cursor) => ref
                      .read(appControllerProvider)
                      .adapter
                      .relationships(_user.id,
                          followers: followers, cursor: cursor)))));

  void _image(String url, Object heroScope) {
    if (safeMediaUrl(url)) {
      Navigator.of(context).push<void>(MediaGalleryRoute<void>(
          child: MediaPage(
              media: [SocialMedia(preview: url)],
              index: 0,
              author: _user.handle,
              heroScope: heroScope,
              heroThumbnailUsesCover: true)));
    }
  }

  Future<void> _share() async {
    final url = 'https://x.com/${_user.handle}';
    try {
      await const MethodChannel('com.review.x/media')
          .invokeMethod('shareText', {'text': url, 'title': '分享个人主页'});
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('主页链接已复制')));
      }
    }
  }

  String? get _joined {
    if (_user.createdAt.isEmpty) return null;
    var date = DateTime.tryParse(_user.createdAt);
    try {
      date ??= DateFormat('EEE MMM dd HH:mm:ss yyyy', 'en_US')
          .parseUtc(_user.createdAt.replaceFirst(RegExp(r' [+-]\d{4} '), ' '));
    } catch (_) {
      /* An unfamiliar date must not appear as an unreadable timestamp. */
    }
    return date == null ? null : '${date.year}年${date.month}月加入';
  }

  Widget _stat(String key, int value, String label, VoidCallback action) =>
      TextButton(
          onPressed: action,
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: Theme.of(context).colorScheme.onSurface),
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: _user.knownCounts.contains(key) ? '$value ' : '— ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(
                text: label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])));

  Widget _tabs() {
    const labels = ['推文', '回复', '转推', '照片', '文章', '喜欢'];
    const icons = [
      Icons.article_outlined,
      Icons.chat_bubble_outline,
      Icons.repeat,
      Icons.photo_library_outlined,
      Icons.description_outlined,
      Icons.favorite_border
    ];
    Widget label(int index) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icons[index], size: 18),
          const SizedBox(width: 6),
          Text(index == 0 && _tweetMode == 'UserHighlightsTweets'
              ? '亮点'
              : index == 3 && _mediaMode == 'UserVideoTimeline'
                  ? '视频'
                  : labels[index]),
          if (index == 0 || index == 3)
            const Icon(Icons.keyboard_arrow_down, size: 16),
        ]);
    return DecoratedBox(
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor))),
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var index = 0; index < labels.length; index++)
                Container(
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                width: 3,
                                color: _category == index
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent))),
                    child: index == 0 || index == 3
                        ? PopupMenuButton<String>(
                            tooltip: index == 0 ? '推文与亮点' : '照片与视频',
                            onSelected: (operation) => setState(() {
                                  _category = index;
                                  if (index == 0) {
                                    _tweetMode = operation;
                                  } else {
                                    _mediaMode = operation;
                                  }
                                }),
                            itemBuilder: (_) => [
                                  for (final entry in (index == 0
                                          ? const {
                                              'UserTweets': '推文',
                                              'UserHighlightsTweets': '亮点'
                                            }
                                          : const {
                                              'UserPhotoTimeline': '照片',
                                              'UserVideoTimeline': '视频'
                                            })
                                      .entries)
                                    CheckedPopupMenuItem(
                                        value: entry.key,
                                        checked: (index == 0
                                                ? _tweetMode
                                                : _mediaMode) ==
                                            entry.key,
                                        child: Text(entry.value))
                                ],
                            child: Semantics(
                                button: true,
                                selected: _category == index,
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 16),
                                    child: label(index))))
                        : TextButton(
                            onPressed: () => setState(() => _category = index),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 16),
                                foregroundColor: _category == index
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                            child: label(index)))
            ])));
  }

  Widget _header() {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final showBanner = ref.watch(readingProvider)['showBanner'] == true;
    final bannerHeight = showBanner ? 120.0 : 38.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          height: bannerHeight + 58,
          child: Stack(children: [
            if (showBanner)
              SizedBox(
                  width: double.infinity,
                  height: bannerHeight,
                  child: _user.banner.isNotEmpty && safeMediaUrl(_user.banner)
                      ? GestureDetector(
                          onTap: () {
                            HapticFeedbackUtil.light();
                            _image(_user.banner, _profileBannerHeroScope);
                          },
                          child: Hero(
                              tag: mediaGalleryHeroTag(
                                _profileBannerHeroScope,
                                0,
                                thumbnailUsesCover: true,
                              ),
                              flightShuttleBuilder:
                                  mediaGalleryHeroFlightShuttleBuilder,
                              child: CachedNetworkImage(_user.banner,
                                  fit: BoxFit.cover)))
                      : ColoredBox(color: colors.surfaceContainerHighest)),
            Positioned(
                left: 16,
                top: showBanner ? bannerHeight - 38 : 8,
                child: GestureDetector(
                    onTap: _user.avatar.isNotEmpty
                        ? () {
                            HapticFeedbackUtil.light();
                            _image(_user.avatar.replaceAll('_bigger.', '.'),
                                _profileAvatarHeroScope);
                          }
                        : null,
                    child: Container(
                        width: 88,
                        height: 88,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: colors.surface, shape: BoxShape.circle),
                        child: ClipOval(
                            child: _user.avatar.isNotEmpty
                                ? Hero(
                                    tag: mediaGalleryHeroTag(
                                      _profileAvatarHeroScope,
                                      0,
                                      thumbnailUsesCover: true,
                                    ),
                                    flightShuttleBuilder:
                                        mediaGalleryHeroFlightShuttleBuilder,
                                    child: CachedNetworkImage(_user.avatar,
                                        fit: BoxFit.cover))
                                : ColoredBox(
                                    color: colors.surfaceContainerHighest,
                                    child:
                                        const Icon(Icons.person, size: 40)))))),
            Positioned(
                right: 16,
                bottom: 8,
                child: _isMe
                    ? OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share_outlined, size: 18),
                        label: const Text('分享'))
                    : FilledButton.tonal(
                        onPressed:
                            _following || _followUncertain ? null : _follow,
                        child: Text(_following
                            ? '提交中…'
                            : _user.isFollowing
                                ? '取消关注'
                                : _user.followRequested
                                    ? '已请求关注'
                                    : _user.protected
                                        ? '请求关注'
                                        : '关注'))),
          ])),
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                  child: Text(_user.name,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold))),
              if (_user.verified)
                Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child:
                        Icon(Icons.verified, size: 20, color: colors.primary))
            ]),
            Text('@${_user.handle}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant)),
            if (_user.followedBy || _user.protected)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      [
                        if (_user.followedBy) '关注了你',
                        if (_user.protected) '受保护的账号'
                      ].join(' · '),
                      style: theme.textTheme.bodySmall)),
            if (_user.description.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_user.description)),
            if (_user.location.isNotEmpty ||
                safeLink(_user.website) ||
                _joined != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_user.location.isNotEmpty)
                          Text('⌖ ${_user.location}',
                              style: TextStyle(color: colors.onSurfaceVariant)),
                        if (safeLink(_user.website))
                          InkWell(
                              onTap: () => launchUrl(Uri.parse(_user.website),
                                  mode: LaunchMode.externalApplication),
                              child: Text(_user.website,
                                  style: TextStyle(color: colors.primary))),
                        if (_joined != null)
                          Text('◷ $_joined',
                              style: TextStyle(color: colors.onSurfaceVariant)),
                      ])),
            Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _stat(
                      'following', _user.following, '正在关注', () => _list(false)),
                  _stat('followers', _user.followers, '关注者', () => _list(true))
                ]),
            if (_profileError != null)
              TextButton(
                  onPressed: _loadProfile, child: const Text('资料加载失败，点击重试')),
          ])),
      _tabs(),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          toolbarHeight:
              MediaQuery.textScalerOf(context).scale(56).clamp(56.0, 112.0),
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_user.knownCounts.contains('postsCount'))
              Text('${_user.postsCount} 推文',
                  style: Theme.of(context).textTheme.bodySmall)
          ]),
          actions: [
            IconButton(
                tooltip: '在 X 打开主页',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => launchUrl(
                    Uri.parse('https://x.com/${_user.handle}'),
                    mode: LaunchMode.externalApplication))
          ]),
      body: _operation == 'Likes' && !_isMe
          ? ListView(children: [
              _header(),
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('X 不公开其他用户的喜欢列表，仅可查看自己的喜欢',
                      textAlign: TextAlign.center))
            ])
          : TimelinePage(
              key: ValueKey('${_user.id}/$_operation'),
              load: (cursor) => ref
                  .read(appControllerProvider)
                  .adapter
                  .userTimeline(_user.id,
                      operation: _operation, cursor: cursor),
              header: _header()));
}
