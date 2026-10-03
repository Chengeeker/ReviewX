import '../api/twitter_client.dart';
import '../models/social_models.dart';
import '../models/content_models.dart';

/// Platform boundary. Widgets never read Twitter JSON or call GraphQL directly.
abstract interface class SocialPlatformAdapter {
  Future<PostPage> home({String? cursor});
  Future<PostPage> forYou({String? cursor});
  Future<PostPage> following({String? cursor});
  Future<List<TrendingTopic>> trends({bool personalized = false});
  Future<PostPage> detail(String id, {String? cursor});
  Future<SocialUser> user(String id);
  Future<PostPage> userPosts(String id, {String? cursor});
  Future<void> like(String id, bool liked);
  Future<void> repost(String id, bool reposted);
}

class TwitterAdapter implements SocialPlatformAdapter {
  TwitterAdapter(this.client);
  final TwitterClient client;
  @override
  Future<PostPage> home({String? cursor}) => following(cursor: cursor);

  @override
  Future<PostPage> forYou({String? cursor}) async {
    final data = await client.call('HomeTimeline', {
      'count': 20,
      'includePromotedContent': true,
      'latestControlAvailable': true,
      'requestContext': 'launch',
      'seenTweetIds': <String>[],
      'withCommunity': true,
      'withQuickPromoteEligibilityTweetFields': true,
      if (cursor != null) 'cursor': cursor
    });
    return _page(object(data['home'])['home_timeline_urt']);
  }

  @override
  Future<PostPage> following({String? cursor}) async {
    final data = await client.call('HomeLatestTimeline', {
      'count': 20,
      'includePromotedContent': false,
      'enableRanking': false,
      'latestControlAvailable': true,
      'requestContext': 'launch',
      'seenTweetIds': <String>[],
      'withCommunity': true,
      'withQuickPromoteEligibilityTweetFields': true,
      if (cursor != null) 'cursor': cursor
    });
    return _page(object(data['home'])['home_timeline_urt']);
  }

  @override
  Future<List<TrendingTopic>> trends({bool personalized = false}) async {
    final data = await client.trendsGuide(personalized: personalized);
    if (object(object(data['timeline']))['instructions'] is! List) {
      throw const TwitterFailure('X 趋势结构已变化，请更新客户端');
    }
    return TrendingTopic.parseGuide(data);
  }

  Future<List<SocialUser>> recommendedUsers() async {
    final id = client.session?.userId;
    if (id == null) throw const TwitterFailure('请登录 X');
    final values = await client.recommendedUsers(id);
    final users = <String, SocialUser>{};
    for (final value in values) {
      final item = object(value), legacy = object(object(value)['user']);
      final user = SocialUser.parse({
        'rest_id': item['user_id'] ?? legacy['id_str'],
        'legacy': legacy,
      });
      if (user != null && user.id != id && !user.isFollowing) {
        users[user.id] = user;
      }
    }
    return users.values.toList(growable: false);
  }

  @override
  Future<PostPage> detail(String id, {String? cursor}) async {
    final data = await client.call('TweetDetail', {
      'focalTweetId': id,
      'referrer': 'tweet',
      'withV2Timeline': true,
      'with_rux_injections': false,
      'rankingMode': 'Relevance',
      'includePromotedContent': false,
      'withCommunity': true,
      'withQuickPromoteEligibilityTweetFields': true,
      'withBirdwatchNotes': true,
      'withVoice': true,
      if (cursor != null) 'cursor': cursor
    });
    return _page(data['threaded_conversation_with_injections_v2']);
  }

  PostPage _page(dynamic timeline) {
    if (timeline is! Map || timeline['instructions'] is! List) {
      throw const TwitterFailure('X 的时间线结构已变化，请更新客户端');
    }
    return PostPage.parse(timeline);
  }

  @override
  Future<SocialUser> user(String id) async {
    final data = await client
        .call('UserByRestId', {'userId': id, 'withSafetyModeUserFields': true});
    final user = SocialUser.parse(object(data['user'])['result']);
    if (user == null) throw const TwitterFailure('用户不可用或接口结构已变化');
    return user;
  }

  @override
  Future<PostPage> userPosts(String id, {String? cursor}) async {
    return userTimeline(id, cursor: cursor);
  }

  Future<PostPage> userTimeline(String id,
      {String operation = 'UserTweets', String? cursor}) async {
    if (!const ['UserTweets', 'UserTweetsAndReplies', 'UserMedia']
        .contains(operation)) {
      throw const TwitterFailure('不支持的用户时间线');
    }
    final data = await client.call(operation, {
      'userId': id,
      'count': 20,
      'includePromotedContent': false,
      'withQuickPromoteEligibilityTweetFields': true,
      'withVoice': true,
      'withCommunity': true,
      'withClientEventToken': false,
      'withBirdwatchNotes': false,
      if (cursor != null) 'cursor': cursor
    });
    final result = object(object(data['user'])['result']);
    final wrapper = object(result['timeline'] ?? result['timeline_v2']);
    return _page(wrapper['timeline'] ?? wrapper);
  }

  Future<SocialUser> userByHandle(String handle) async {
    final data = await client.call('UserByScreenName',
        {'screen_name': handle, 'withSafetyModeUserFields': true});
    final user = SocialUser.parse(object(data['user'])['result']);
    if (user == null) throw const TwitterFailure('用户不可用或接口结构已变化');
    return user;
  }

  Future<SocialUser> validateSession({void Function(String)? onStage}) async {
    final session = client.session;
    if (session == null) throw const TwitterFailure('请登录 X');
    onStage?.call('确认 X 当前账号');
    final settings = await client.accountSettings();
    if (!identical(client.session, session)) {
      throw const TwitterFailure('账号已切换');
    }
    final handle = settings['screen_name'];
    if (handle is! String || handle.isEmpty) {
      throw const TwitterFailure('X 未返回当前账号身份，请重新登录');
    }
    onStage?.call('读取用户资料');
    final profile = await user(session.userId);
    if (!identical(client.session, session)) {
      throw const TwitterFailure('账号已切换');
    }
    if (profile.handle.toLowerCase() != handle.toLowerCase()) {
      throw const TwitterFailure('X 当前账号与会话标识不一致，请重新登录');
    }
    return profile;
  }

  Future<dynamic> _search(String query, String product, String? cursor) async {
    final data = await client.call('SearchTimeline', {
      'rawQuery': query,
      'count': 20,
      'querySource': 'typed_query',
      'product': product,
      if (cursor != null) 'cursor': cursor
    });
    final timeline = object(
        object(data['search_by_raw_query'])['search_timeline'])['timeline'];
    if (timeline is! Map || timeline['instructions'] is! List) {
      throw const TwitterFailure('X 搜索结构已变化，请更新客户端');
    }
    return timeline;
  }

  Future<PostPage> search(String query,
          {String product = 'Top', String? cursor}) async =>
      _page(await _search(query, product, cursor));
  Future<UserPage> searchUsers(String query, {String? cursor}) async =>
      UserPage.parse(await _search(query, 'People', cursor));

  Future<UserPage> relationships(String id,
      {required bool followers, String? cursor}) async {
    final data = await client.call(followers ? 'Followers' : 'Following', {
      'userId': id,
      'count': 20,
      'includePromotedContent': false,
      if (cursor != null) 'cursor': cursor
    });
    final result = object(object(data['user'])['result']);
    final wrapper = object(result['timeline'] ?? result['timeline_v2']);
    final timeline = wrapper['timeline'] ?? wrapper;
    if (timeline['instructions'] is! List) {
      throw const TwitterFailure('X 用户列表结构已变化');
    }
    return UserPage.parse(timeline);
  }

  Future<SocialUser> follow(String id, bool following) async {
    await client.rest(
        following
            ? '/1.1/friendships/create.json'
            : '/1.1/friendships/destroy.json',
        {
          'user_id': id,
          'include_following': 1,
          'include_followed_by': 1,
          'skip_status': 1
        });
    try {
      final updated = await user(id);
      if (updated.isFollowing != following &&
          !(following && updated.protected && updated.followRequested)) {
        throw const TwitterFailure('关注状态未确认，请刷新主页核对', uncertain: true);
      }
      return updated;
    } catch (_) {
      throw const TwitterFailure('关注结果待确认，请刷新主页核对后再操作', uncertain: true);
    }
  }

  Future<NotificationPageData> notifications({String? cursor}) async {
    final data = await client.call('NotificationsTimeline', {
      'timeline_type': 'All',
      'count': 20,
      if (cursor != null) 'cursor': cursor
    });
    final timeline = object(
        object(object(object(data['viewer_v2'])['user_results'])['result'])[
            'notification_timeline'])['timeline'];
    if (timeline is! Map || timeline['instructions'] is! List) {
      throw const TwitterFailure('X 通知结构已变化，请更新客户端');
    }
    return NotificationPageData.parse(timeline);
  }

  Future<void> markNotificationsRead(String topCursor) async {
    await client.rest(
        '/2/notifications/all/last_seen_cursor.json', {'cursor': topCursor});
  }

  Future<SocialPost> article(String postId) async {
    final data = await client.call('TweetResultByRestId', {
      'tweetId': postId,
      'withCommunity': false,
      'includePromotedContent': false,
      'withVoice': false
    });
    final post = SocialPost.parse(object(data['tweetResult'])['result']);
    if (post == null || post.article == null) {
      throw const TwitterFailure('这篇文章暂不可用，请在 X 查看');
    }
    return post;
  }

  Future<PostPage> bookmarks({String? cursor}) async {
    final data = await client.call('Bookmarks', {
      'count': 20,
      'includePromotedContent': false,
      if (cursor != null) 'cursor': cursor
    });
    return _page(object(data['bookmark_timeline_v2'])['timeline']);
  }

  Future<void> bookmark(String id, bool bookmarked) async {
    final data = await client.call(
        bookmarked ? 'CreateBookmark' : 'DeleteBookmark', {'tweet_id': id});
    if (data[bookmarked ? 'tweet_bookmark_put' : 'tweet_bookmark_delete'] !=
        'Done') {
      throw const TwitterFailure('书签结果未确认，请刷新核对', uncertain: true);
    }
  }

  Future<String> publish(String text,
      {String? replyId, String? quoteUrl}) async {
    if (text.trim().isEmpty && quoteUrl == null) {
      throw const TwitterFailure('请输入帖子正文');
    }
    final data = await client.call('CreateTweet', {
      'tweet_text': text,
      'dark_request': false,
      'media': {'media_entities': <dynamic>[], 'possibly_sensitive': false},
      'semantic_annotation_ids': <dynamic>[],
      if (replyId != null)
        'reply': {
          'in_reply_to_tweet_id': replyId,
          'exclude_reply_user_ids': <String>[]
        },
      if (quoteUrl != null) 'attachment_url': quoteUrl
    });
    final result =
        object(object(object(data['create_tweet'])['tweet_results'])['result']);
    final id = '${result['rest_id'] ?? ''}';
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      throw const TwitterFailure('发布结果待确认，请在 X 核对，避免重复发布', uncertain: true);
    }
    return id;
  }

  @override
  Future<void> like(String id, bool liked) async {
    final operation = liked ? 'FavoriteTweet' : 'UnfavoriteTweet';
    final data = await client.call(operation, {'tweet_id': id});
    if (data[liked ? 'favorite_tweet' : 'unfavorite_tweet'] != 'Done') {
      throw const TwitterFailure('操作结果未确认，请刷新核对', uncertain: true);
    }
  }

  @override
  Future<void> repost(String id, bool reposted) async {
    final data = await client.call(reposted ? 'CreateRetweet' : 'DeleteRetweet',
        {reposted ? 'tweet_id' : 'source_tweet_id': id, 'dark_request': false});
    final result = object(object(data['create_retweet'] ?? data['unretweet'])[
        'retweet_results'])['result'];
    if (result is! Map || result['rest_id'] == null) {
      throw const TwitterFailure('转发结果未确认，请刷新核对', uncertain: true);
    }
  }
}
