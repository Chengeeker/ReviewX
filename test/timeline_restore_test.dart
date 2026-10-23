import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/timeline_page.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/app_controller.dart';
import 'package:review_x/twitter/auth/session.dart';
import 'package:review_x/twitter/cache/local_x_cache.dart';
import 'package:review_x/twitter/models/social_models.dart';

const author = SocialUser(id: '1', name: '用户', handle: 'user');
const saved = SocialPost(id: '10', author: author, text: '上次阅读的帖子');
const latest = SocialPost(id: '11', author: author, text: '新加载的帖子');

void main() {
  for (final refresh in [true, false]) {
    testWidgets(
        'cached home waits for explicit ${refresh ? 'refresh' : 'load more'}',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();
      final cache = LocalXCache(storage);
      await cache.writeTimeline('1', 'for_you', [saved]);
      final app = AppController(
          client: TwitterClient()
            ..session = const TwitterSession('auth_token=test; ct0=test', '1'));
      final calls = <bool?>[];
      await tester.pumpWidget(ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            appControllerProvider.overrideWith((ref) => app),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: TimelinePage(
            cacheKey: 'for_you',
            load: (String? cursor,
                {bool? refresh, List<String>? seenIds}) async {
              calls.add(refresh);
              expect(cursor, isNull);
              expect(seenIds, ['10']);
              return const PostPage([latest], 'next');
            },
          )))));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('上次阅读的帖子'), findsOneWidget);
      expect(find.textContaining('正在连接 X'), findsNothing);
      expect(find.text('没有更多帖子'), findsNothing);
      // Account/profile updates must not refresh a restored timeline.
      app.ingest(const []);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      if (refresh) {
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
      } else {
        await tester.tap(find.text('加载更多'));
      }
      await tester.pumpAndSettle();
      expect(calls, [refresh]);
      expect(find.text('新加载的帖子'), findsOneWidget);
      expect(find.text('上次阅读的帖子'), refresh ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty home still loads automatically', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    var calls = 0;
    final app = AppController(
        client: TwitterClient()
          ..session = const TwitterSession('auth_token=test; ct0=test', '1'));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          appControllerProvider.overrideWith((ref) => app),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: TimelinePage(
          cacheKey: 'following',
          load: (cursor) async {
            calls++;
            return const PostPage([latest], null);
          },
        )))));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('新加载的帖子'), findsOneWidget);
  });
}
