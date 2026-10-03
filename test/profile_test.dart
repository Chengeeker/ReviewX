import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/timeline_page.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/app_controller.dart';
import 'package:review_x/twitter/auth/session.dart';
import 'package:review_x/twitter/models/social_models.dart';
import 'package:review_x/twitter/repositories/twitter_adapter.dart';
import 'twitter_test.dart' as fixtures;

const initialUser = SocialUser(
    id: '1',
    name: '测试用户',
    handle: 'test',
    followers: 1,
    following: 11,
    postsCount: 3,
    createdAt: 'Thu Dec 15 10:05:38 +0000 2022');
Map<String, dynamic> modernUser() => {
      'rest_id': '1',
      'core': {
        'name': '测试用户',
        'screen_name': 'test',
        'created_at': initialUser.createdAt
      },
      'relationship_counts': {'followers': 1, 'following': 11},
      'tweet_counts': {'tweets': 3},
      'banner': {'image_url': 'https://pbs.twimg.com/banner.jpg'},
      'website': {'url': 'https://example.com'},
      'profile_description': {'description': '新的资料结构'},
    };

class ProfileClient extends TwitterClient {
  bool emptyTimeline = false;
  final calls = <String>[];
  final variables = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pendingProfile, pendingPosts;
  Map<String, dynamic> profile = modernUser()..remove('banner');
  @override
  Future<Map<String, dynamic>> call(
      String operation, Map<String, dynamic> values) async {
    calls.add(operation);
    variables.add(Map.of(values));
    if (operation == 'UserByRestId') {
      return pendingProfile?.future ??
          {
            'user': {'result': profile}
          };
    }
    return pendingPosts?.future ??
        {
          'user': {
            'result': {
              'timeline': {
                'timeline':
                    emptyTimeline ? {'instructions': []} : fixtures.timeline()
              }
            }
          }
        };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'modern statistics take precedence; missing fields preserve known counts and explicit zero clears',
      () {
    final raw = modernUser()
      ..['legacy'] = {
        'followers_count': 99,
        'friends_count': 99,
        'statuses_count': 99
      };
    final user = SocialUser.parse(raw)!;
    expect([user.followers, user.following, user.postsCount], [1, 11, 3]);
    expect(user.description, '新的资料结构');
    expect(user.banner, 'https://pbs.twimg.com/banner.jpg');
    expect(user.website, 'https://example.com');
    final missing = SocialUser.parse({'rest_id': '1', 'core': raw['core']})!;
    expect(missing.knownCounts, isEmpty);
    final cached =
        SocialUser.fromCacheJson(missing.toCacheJson())!.preservingCounts(user);
    expect([cached.followers, cached.following, cached.postsCount], [1, 11, 3]);
    raw['relationship_counts'] = {'followers': 0, 'following': 0};
    raw['tweet_counts'] = {'tweets': 0};
    final zero = SocialUser.parse(raw)!.preservingCounts(user);
    expect([zero.followers, zero.following, zero.postsCount], [0, 0, 0]);
    expect(
        missing
            .preservingCounts(const SocialUser(
                id: '2', name: 'other', handle: 'other', followers: 99))
            .followers,
        0);
  });

  test(
      'each profile route has protocol metadata and keeps pagination; likes guard other accounts',
      () async {
    final client = ProfileClient()
      ..session = const TwitterSession('auth_token=test; ct0=test', '1');
    final adapter = TwitterAdapter(client);
    final protocol =
        jsonDecode(await rootBundle.loadString('assets/twitter_protocol.json'))
            as Map;
    for (final route in [
      'UserTweets',
      'UserTweetsAndReplies',
      'UserHighlightsTweets',
      'UserRepostsTimeline',
      'UserPhotoTimeline',
      'UserVideoTimeline',
      'UserArticlesTweets',
      'Likes'
    ]) {
      final page =
          await adapter.userTimeline('1', operation: route, cursor: 'next');
      expect(client.calls.last, route);
      expect(client.variables.last['cursor'], 'next');
      expect(page.posts.length, 2);
      expect(protocol[route]['method'], 'GET');
      expect(protocol[route]['id'], isNotEmpty);
      if (route == 'UserHighlightsTweets') {
        expect(client.variables.last['sortByMostLiked'], false);
      }
    }
    final before = client.calls.length;
    await expectLater(adapter.userTimeline('2', operation: 'Likes'),
        throwsA(isA<TwitterFailure>()));
    expect(client.calls.length, before);
  });

  testWidgets(
      'profile statistics survive delayed partial profile and posts; tabs use independent routes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final client = ProfileClient()
      ..session = const TwitterSession('auth_token=test; ct0=test', '1');
    client.emptyTimeline = true;
    client.pendingProfile = Completer();
    client.pendingPosts = Completer();
    final app = AppController(client: client)..ready = true;
    await tester.pumpWidget(ProviderScope(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      appControllerProvider.overrideWith((ref) => app)
    ], child: const MaterialApp(home: ProfilePage(user: initialUser))));
    await tester.pump();
    expect(find.text('11 正在关注'), findsOneWidget);
    client.pendingProfile!.complete({
      'user': {
        'result': {
          'rest_id': '1',
          'core': {
            'name': '测试用户',
            'screen_name': 'test',
            'created_at': initialUser.createdAt
          }
        }
      }
    });
    await tester.pump();
    await tester.pump();
    client.pendingPosts!.complete({
      'user': {
        'result': {
          'timeline': {
            'timeline': {'instructions': []}
          }
        }
      }
    });
    client.pendingPosts = null;
    await tester.pumpAndSettle();
    expect(find.text('11 正在关注'), findsOneWidget);
    expect(find.text('1 关注者'), findsOneWidget);
    expect(find.text('◷ 2022年12月加入'), findsOneWidget);
    await tester.tap(find.byTooltip('推文与亮点'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, '亮点'));
    await tester.pumpAndSettle();
    expect(client.calls.last, 'UserHighlightsTweets');
    await tester.ensureVisible(find.byTooltip('照片与视频'));
    await tester.tap(find.byTooltip('照片与视频'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, '视频'));
    await tester.pumpAndSettle();
    expect(client.calls.last, 'UserVideoTimeline');
    await tester.ensureVisible(find.text('文章'));
    await tester.tap(find.text('文章'));
    await tester.pumpAndSettle();
    expect(client.calls.last, 'UserArticlesTweets');
    await tester.ensureVisible(find.text('喜欢'));
    await tester.tap(find.text('喜欢'));
    await tester.pumpAndSettle();
    expect(client.calls.last, 'Likes');
    await tester.ensureVisible(find.text('转推'));
    await tester.tap(find.text('转推'));
    await tester.pumpAndSettle();
    expect(client.calls.last, 'UserRepostsTimeline');
    await tester.ensureVisible(find.text('回复'));
    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();
    expect(client.calls.last, 'UserTweetsAndReplies');

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'profile stays usable on narrow phones with large text and does not request other likes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = ProfileClient()..emptyTimeline = true;
    client.session = const TwitterSession('auth_token=test; ct0=test', '2');
    final app = AppController(client: client)..ready = true;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          appControllerProvider.overrideWith((ref) => app)
        ],
        child: const MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(2)),
                child: ProfilePage(user: initialUser)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('喜欢'));
    await tester.tap(find.text('喜欢'));
    await tester.pumpAndSettle();
    expect(find.text('X 不公开其他用户的喜欢列表，仅可查看自己的喜欢'), findsOneWidget);
    expect(client.calls, isNot(contains('Likes')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
