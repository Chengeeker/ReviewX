import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/core/theme/app_theme.dart';
import 'package:review_x/presentation/home_page.dart';
import 'package:review_x/presentation/timeline_page.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/app_controller.dart';
import 'package:review_x/twitter/auth/session.dart';
import 'package:review_x/twitter/models/social_models.dart';
import 'package:review_x/presentation/post_card.dart';
import 'package:review_x/presentation/discovery_pages.dart';
import 'package:review_x/twitter/models/content_models.dart';

const sampleUser = SocialUser(id: '1', name: 'Review X', handle: 'reviewx');
const sample = SocialPost(
    id: '2', author: sampleUser, text: '测试帖子', liked: true, likes: 4);

class ExploreClient extends TwitterClient {
  final categories = <bool>[];
  @override
  Future<Map<String, dynamic>> trendsGuide(
      {int count = 20, bool personalized = false}) async {
    categories.add(personalized);
    return {
      'timeline': {
        'instructions': [
          {
            'addEntries': {
              'entries': [
                {
                  'content': {
                    'item': {
                      'content': {
                        'trend': {
                          'name': personalized ? '推荐趋势' : '实时趋势',
                          'description': '美国 的趋势'
                        }
                      }
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    };
  }

  @override
  Future<List<dynamic>> recommendedUsers(String userId) async => [
        {
          'user_id': '7',
          'user': {'id_str': '7', 'screen_name': 'recommended', 'name': '推荐用户'}
        }
      ];
}

class SlowClient extends TwitterClient {
  final finish = Completer<Map<String, dynamic>>();
  int calls = 0;
  @override
  Future<Map<String, dynamic>> call(
      String operation, Map<String, dynamic> variables) {
    calls++;
    return finish.future;
  }
}

class FeedClient extends TwitterClient {
  @override
  Future<Map<String, dynamic>> call(
      String operation, Map<String, dynamic> variables) async {
    if (operation != 'HomeTimeline' && operation != 'HomeLatestTimeline') {
      throw StateError('Unexpected operation: $operation');
    }
    return {
      'home': {
        'home_timeline_urt': {
          'instructions': [
            {
              'type': 'TimelineAddEntries',
              'entries': [
                for (var index = 0; index < 32; index++)
                  {
                    'content': {
                      'itemContent': {
                        'tweet_results': {
                          'result': {
                            'rest_id': '${index + 100}',
                            'core': {
                              'user_results': {
                                'result': {
                                  'rest_id': '1',
                                  'core': {
                                    'screen_name': 'reviewx',
                                    'name': 'Review X'
                                  }
                                }
                              }
                            },
                            'legacy': {'full_text': '第 $index 条帖子'}
                          }
                        }
                      }
                    }
                  }
              ]
            }
          ]
        }
      }
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'media inherits no floating bar padding and actions stay adjacent',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    const post =
        SocialPost(id: 'media', author: sampleUser, text: '带图片', media: [
      SocialMedia(
          preview: 'https://pbs.twimg.com/test.jpg', width: 400, height: 300),
    ]);
    await tester.pumpWidget(ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
            home: Scaffold(
                body: MediaQuery(
                    data: const MediaQueryData(
                        padding: EdgeInsets.only(bottom: 120)),
                    child: ListView(
                        padding: EdgeInsets.zero,
                        children: const [PostCard(post: post)]))))));
    // Image loading animates independently; this regression checks layout only.
    await tester.pump(const Duration(milliseconds: 100));
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.padding, EdgeInsets.zero);
    expect(grid.primary, isFalse);
    final media = tester.getRect(find.byType(MediaGrid));
    final actions = tester
        .getRect(find.widgetWithIcon(TextButton, Icons.chat_bubble_outline));
    expect(actions.top - media.bottom, lessThan(12));
    expect(tester.getTopLeft(find.text('带图片')).dx, greaterThan(50));
    expect(tester.takeException(), isNull);
  });
  testWidgets('explore starts personalized with region and recommendations',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final api = ExploreClient()
      ..session = const TwitterSession('auth_token=stub; ct0=stub', '1');
    final controller = AppController(client: api);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          appControllerProvider.overrideWith((ref) => controller)
        ],
        child: const MaterialApp(
            home: Scaffold(body: SearchPage(showExplore: true)))));
    await tester.pumpAndSettle();
    expect(api.categories, [true]);
    expect(find.text('美国 的趋势'), findsOneWidget);
    expect(find.text('推荐用户'), findsOneWidget);
    expect(find.text('推荐关注'), findsOneWidget);
    await tester.tap(find.text('当前趋势').first);
    await tester.pumpAndSettle();
    expect(api.categories, [true, false]);
    expect(find.text('实时趋势'), findsOneWidget);
    expect(find.text('推荐关注'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
      'cross-page optimistic unlike blocks duplicate taps and rolls back uncertain writes',
      () async {
    final client = SlowClient();
    final controller = AppController(client: client);
    final action = controller.act(sample, like: true);
    expect(controller.effective(sample).liked, isFalse);
    expect(controller.effective(sample).likes, 3);
    await controller.act(sample, like: true);
    expect(client.calls, 1);
    final assertion = expectLater(action, throwsA(isA<TwitterFailure>()));
    client.finish.completeError(const TwitterFailure('结果待确认', uncertain: true));
    await assertion;
    expect(controller.effective(sample).liked, isTrue);
    expect(controller.actionBlocked(sample.id), isTrue);
    controller.ingest([sample.withActions(liked: false)]);
    expect(controller.actionBlocked(sample.id), isFalse);
    expect(controller.effective(sample).liked, isFalse);
    controller.dispose();
  });
  testWidgets(
      'landing and settings render without login, preserve theme preferences',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final boundary = GlobalKey();
    await tester.pumpWidget(ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
            theme: AppTheme.lightTheme(colorIndex: 2).copyWith(
                appBarTheme: AppTheme.lightTheme(colorIndex: 2)
                    .appBarTheme
                    .copyWith(
                        titleTextStyle: AppTheme.lightTheme(colorIndex: 2)
                            .appBarTheme
                            .titleTextStyle
                            ?.copyWith(fontFamily: 'PreviewFont')),
                textTheme: AppTheme.lightTheme(colorIndex: 2)
                    .textTheme
                    .apply(fontFamily: 'PreviewFont')),
            home: RepaintBoundary(key: boundary, child: const HomePage()))));
    await tester.pumpAndSettle();
    expect(find.text('登录 X'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final repaint =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await repaint.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/previews').create(recursive: true);
      await File('build/previews/landing.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('登录 X'));
    await tester.pumpAndSettle();
    expect(find.text('Cookie 登录 X'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('个性化'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Material You (Monet) 动态取色'));
    expect(find.text('Material You (Monet) 动态取色'), findsOneWidget);
    await tester.tap(find.text('Material You (Monet) 动态取色'));
    await tester.pumpAndSettle();
    expect(storage.getBool(StorageService.keyUseDynamicColor), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty refresh retains rows and cursor continuation advances',
      (tester) async {
    final cursors = <String?>[];
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    var page = 0;
    await tester.pumpWidget(ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child:
            MaterialApp(home: Scaffold(body: TimelinePage(load: (cursor) async {
          cursors.add(cursor);
          page++;
          if (page == 1) return const PostPage([sample], 'bottom');
          if (page == 2) return const PostPage([sample], null);
          return const PostPage([], null);
        })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(cursors, [null, 'bottom']);
    expect(find.text('测试帖子'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('测试帖子'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'cached feed shows pending and failed refresh above rows and retries',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final pending = Completer<PostPage>();
    var calls = 0;
    await tester.pumpWidget(ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
            home: Scaffold(
                body: TimelinePage(
          initial: const [sample],
          load: (cursor) {
            calls++;
            expect(cursor, isNull);
            return calls == 1
                ? pending.future
                : Future.value(const PostPage([sample], null));
          },
        )))));
    await tester.pump();
    expect(find.textContaining('正在连接 X'), findsOneWidget);
    expect(find.text('测试帖子'), findsOneWidget);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    expect(calls, 1);
    pending
        .completeError(const TwitterFailure('连接 X 超时，请检查 VPN 或代理是否开启及可用，然后重试'));
    await tester.pumpAndSettle();
    final error = find.textContaining('连接 X 超时');
    expect(error, findsOneWidget);
    expect(tester.getTopLeft(error).dy,
        lessThan(tester.getTopLeft(find.text('测试帖子')).dy));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(error, findsNothing);
    expect(find.text('测试帖子'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('floating capsule leaves the home timeline scrollable',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final client = FeedClient()
      ..session = const TwitterSession('auth_token=stub; ct0=stub', '1');
    final controller = AppController(client: client);
    await tester.pumpWidget(ProviderScope(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      appControllerProvider.overrideWith((ref) => controller),
    ], child: const MaterialApp(home: HomePage())));
    await tester.pumpAndSettle();
    final list = find.byType(ListView).first;
    final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(list, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'article and poll card remain usable at large font on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final rich = SocialPost(
        id: '4',
        author: sampleUser,
        text: '文章与投票',
        createdAt: DateTime.utc(2025, 1, 1),
        article:
            const SocialArticle(id: 'a', title: '测试文章标题', preview: '服务器返回的摘要'),
        poll: const SocialPoll(['第一项', '第二项'], [5, 2], null, null),
        likes: 999999,
        reposts: 999999,
        replies: 999999);
    await tester.pumpWidget(ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.8)),
                child: child!),
            home: Scaffold(body: ListView(children: [PostCard(post: rich)])))));
    await tester.pumpAndSettle();
    expect(find.text('测试文章标题'), findsOneWidget);
    expect(find.text('在 X 投票'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
