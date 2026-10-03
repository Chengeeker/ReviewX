import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/widgets/cached_network_image.dart';
import '../core/storage/reading_settings.dart';
import '../core/storage/storage_service.dart';
import '../twitter/api/twitter_client.dart';
import '../twitter/models/content_models.dart';
import 'discovery_pages.dart';
import 'media_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/cache/local_x_cache.dart';
import '../twitter/models/social_models.dart';
import 'post_card.dart';

typedef PageLoader = Future<PostPage> Function(String? cursor);

class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage(
      {super.key,
      required this.load,
      this.header,
      this.initial = const [],
      this.cacheKey});
  final PageLoader load;
  final Widget? header;
  final List<SocialPost> initial;
  final String? cacheKey;
  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  late List<SocialPost> _posts = widget.initial;
  String? _cursor, _error;
  bool _loading = false, _loaded = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    final cacheKey = widget.cacheKey;
    final controller = ref.read(appControllerProvider);
    final accountId = controller.client.session?.userId;
    if (cacheKey != null && accountId != null) {
      _posts = ref.read(localXCacheProvider).readTimeline(accountId, cacheKey);
      _loaded = _posts.isNotEmpty;
    }
    _fetch(refresh: true);
  }

  Future<void> _fetch({bool refresh = false}) async {
    if (_loading) return;
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
        _loaded = true;
      });
    } catch (error) {
      controller.report(error);
      if (mounted && generation == _request && controller.epoch == epoch) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _request) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: () => _fetch(refresh: true),
      child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom > 24
                  ? MediaQuery.paddingOf(context).bottom
                  : 24),
          itemCount: _posts.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) return widget.header ?? const SizedBox.shrink();
            if (index <= _posts.length) {
              return PostCard(
                  key: ValueKey(_posts[index - 1].id), post: _posts[index - 1]);
            }
            return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  if (_error != null)
                    Text(_error!, textAlign: TextAlign.center),
                  if (_loading) const CircularProgressIndicator(),
                  if (!_loading && _error != null)
                    FilledButton.tonal(
                        onPressed: () => _fetch(refresh: !_loaded),
                        child: const Text('重试')),
                  if (!_loading && _error == null && _cursor != null)
                    FilledButton.tonal(
                        onPressed: _fetch, child: const Text('加载更多')),
                  if (!_loading && _error == null && _cursor == null)
                    Text(_posts.isEmpty ? '暂无帖子，下拉刷新' : '没有更多帖子')
                ]));
          }));
}

class PostDetailPage extends ConsumerStatefulWidget {
  const PostDetailPage({super.key, required this.post});
  final SocialPost post;
  @override
  ConsumerState<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends ConsumerState<PostDetailPage> {
  @override
  void initState() {
    super.initState();
    final account = ref.read(appControllerProvider).client.session?.userId;
    if (account != null && ref.read(readingProvider)['saveHistory'] == true) {
      BrowsingHistory(ref.read(storageServiceProvider)).add(account,
          id: widget.post.id,
          url: widget.post.url,
          title: widget.post.text,
          author: widget.post.author.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final controller = ref.read(appControllerProvider);
    return Scaffold(
        appBar: AppBar(title: const Text('帖子详情')),
        body: TimelinePage(
            header: PostCard(post: post, detail: true),
            load: (cursor) async {
              final page =
                  await controller.adapter.detail(post.id, cursor: cursor);
              controller.ingest(page.posts);
              // Focal tweet stays in the header; remaining rows contain reply chains.
              return PostPage(
                  page.posts.where((item) => item.id != post.id).toList(),
                  page.cursor);
            }));
  }
}

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, required this.user});
  final SocialUser user;
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late SocialUser _user = widget.user;
  String? _profileError;
  String _operation = 'UserTweets';
  bool _following = false, _followUncertain = false;
  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    try {
      final user = await controller.adapter.user(_user.id);
      if (mounted && controller.epoch == epoch) {
        setState(() {
          _user = user;
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
      if (mounted && controller.epoch == epoch) setState(() => _user = updated);
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

  void _image(String url) {
    if (safeMediaUrl(url)) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MediaPage(
                  media: [SocialMedia(preview: url)],
                  index: 0,
                  author: _user.handle)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(_user.name), actions: [
        IconButton(
            tooltip: '在 X 打开主页',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(
                Uri.parse('https://x.com/${_user.handle}'),
                mode: LaunchMode.externalApplication))
      ]),
      body: TimelinePage(
          key: ValueKey('${_user.id}/$_operation'),
          load: (cursor) => ref
              .read(appControllerProvider)
              .adapter
              .userTimeline(_user.id, operation: _operation, cursor: cursor),
          header: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ref.watch(readingProvider)['showBanner'] == true &&
                        _user.banner.isNotEmpty &&
                        safeMediaUrl(_user.banner))
                      GestureDetector(
                          onTap: () => _image(_user.banner),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: CachedNetworkImage(_user.banner,
                                  width: double.infinity,
                                  height: 130,
                                  fit: BoxFit.cover))),
                    const SizedBox(height: 12),
                    Row(children: [
                      if (_user.avatar.isNotEmpty)
                        GestureDetector(
                            onTap: () => _image(
                                _user.avatar.replaceAll('_bigger.', '.')),
                            child: ClipOval(
                                child: CachedNetworkImage(_user.avatar,
                                    width: 64, height: 64, fit: BoxFit.cover))),
                      const Spacer(),
                      if (_user.id !=
                          ref
                              .read(appControllerProvider)
                              .client
                              .session
                              ?.userId)
                        FilledButton.tonal(
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
                                            : '关注')),
                    ]),
                    const SizedBox(height: 12),
                    Text(_user.name,
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text('@${_user.handle}'),
                    const SizedBox(height: 12),
                    Text(_user.description),
                    const SizedBox(height: 12),
                    if (_user.followedBy) const Text('关注了你'),
                    if (_user.protected) const Text('受保护的账号'),
                    if (_user.location.isNotEmpty) Text('⌖ ${_user.location}'),
                    if (safeLink(_user.website))
                      TextButton(
                          onPressed: () => launchUrl(Uri.parse(_user.website),
                              mode: LaunchMode.externalApplication),
                          child: Text(_user.website)),
                    if (_user.createdAt.isNotEmpty)
                      Text('加入时间：${_user.createdAt}'),
                    Wrap(children: [
                      TextButton(
                          onPressed: () => _list(false),
                          child: Text('${_user.following} 关注')),
                      TextButton(
                          onPressed: () => _list(true),
                          child: Text('${_user.followers} 关注者')),
                      Text('${_user.postsCount} 帖子')
                    ]),
                    if (_profileError != null)
                      TextButton(
                          onPressed: _loadProfile,
                          child: Text('点击刷新资料：$_profileError')),
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final entry in const {
                            'UserTweets': '帖子',
                            'UserTweetsAndReplies': '回复',
                            'UserMedia': '媒体'
                          }.entries)
                            Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                    label: Text(entry.value),
                                    selected: _operation == entry.key,
                                    onSelected: (_) =>
                                        setState(() => _operation = entry.key)))
                        ])),
                  ]))));
}
