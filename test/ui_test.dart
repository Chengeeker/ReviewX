import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:extended_image/extended_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/core/theme/app_theme.dart';
import 'package:review_x/presentation/home_page.dart';
import 'package:review_x/presentation/timeline_page.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/app_controller.dart';
import 'package:review_x/twitter/auth/session.dart';
import 'package:review_x/twitter/models/social_models.dart';
import 'package:review_x/presentation/media_page.dart';
import 'package:review_x/presentation/post_card.dart';
import 'package:review_x/presentation/discovery_pages.dart';
import 'package:review_x/presentation/settings_pages.dart';
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

class OfflineDetailClient extends TwitterClient {
  @override
  Future<Map<String, dynamic>> call(
          String operation, Map<String, dynamic> variables) async =>
      throw const TwitterFailure('模拟网络不可用');
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
    final actions =
        tester.getRect(find.byKey(const ValueKey('post-action-row')));
    expect(actions.top - media.bottom, lessThan(12));
    expect(tester.getTopLeft(find.text('带图片')).dx, 12);
    expect(tester.takeException(), isNull);
  });
  testWidgets('image tap expands into Hero gallery with synced thumbnails',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    const post = SocialPost(
        id: 'hero-gallery',
        author: sampleUser,
        text: '多图帖子',
        media: [
          SocialMedia(
              preview: 'https://pbs.twimg.com/hero-a.jpg',
              width: 800,
              height: 600),
          SocialMedia(
              preview: 'https://pbs.twimg.com/hero-b.jpg',
              width: 800,
              height: 600),
          SocialMedia(
              preview: 'https://pbs.twimg.com/hero-c.jpg',
              width: 800,
              height: 600),
        ]);
    await tester.pumpWidget(ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: Scaffold(body: PostCard(post: post)))));
    await tester.pump(const Duration(milliseconds: 100));

    final sourceTags = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((hero) => hero.tag)
        .toList();
    expect(sourceTags, hasLength(3));

    await tester.tap(find.byKey(const ValueKey('post-media-hero-gallery-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    expect(
        find.byKey(const ValueKey('gallery-thumbnail-strip')), findsOneWidget);
    final galleryPage = find.byType(ExtendedImageGesturePageView);
    final galleryViewport = tester.getRect(galleryPage);
    expect(galleryViewport, const Rect.fromLTWH(0, 0, 1000, 1800));
    expect(
      galleryViewport.overlaps(
        tester.getRect(find.byKey(const ValueKey('gallery-thumbnail-strip'))),
      ),
      isTrue,
    );
    await tester.tapAt(const Offset(500, 900));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(galleryPage), galleryViewport);
    await tester.tapAt(const Offset(500, 900));
    await tester.pump(const Duration(milliseconds: 200));
    final galleryTags = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((hero) => hero.tag)
        .toList();
    expect(galleryTags.where((tag) => tag == sourceTags.first), hasLength(2));
    final pairedHeroes = tester
        .widgetList<Hero>(find.byType(Hero))
        .where((hero) => hero.tag == sourceTags.first)
        .toList();
    expect(pairedHeroes, hasLength(2));
    expect(
        pairedHeroes.every((hero) =>
            hero.flightShuttleBuilder == mediaGalleryHeroFlightShuttleBuilder),
        isTrue);

    await tester.drag(
      find.byType(ExtendedImageGesturePageView),
      const Offset(-520, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('2 / 3'), findsOneWidget);
    final heroTagsAfterPageChange = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((hero) => hero.tag)
        .toList();
    expect(
      heroTagsAfterPageChange.where((tag) => tag == sourceTags.first),
      hasLength(1),
      reason: 'the previously viewed gallery page must not remain a Hero',
    );
    expect(
      heroTagsAfterPageChange.where((tag) => tag == sourceTags[1]),
      hasLength(2),
      reason: 'only the current gallery page pairs with its feed thumbnail',
    );

    await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('3 / 3'), findsOneWidget);
    final heroTagsAfterSecondSwipe = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((hero) => hero.tag)
        .toList();
    expect(heroTagsAfterSecondSwipe.where((tag) => tag == sourceTags[1]),
        hasLength(1));
    expect(heroTagsAfterSecondSwipe.where((tag) => tag == sourceTags[2]),
        hasLength(2));

    await tester.drag(find.byKey(const ValueKey('gallery-thumbnail-strip')),
        const Offset(140, 0));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('2 / 3'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
  testWidgets('reverse Hero flight keeps active gallery child until exit',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final heroTag = mediaGalleryHeroTag(
      Object(),
      0,
      imageAspectRatio: 9 / 16,
      thumbnailUsesCover: true,
    );
    final thumbnail = find.byKey(const ValueKey('return-thumbnail'));
    final galleryImage = find.byKey(const ValueKey('return-gallery-image'));
    final returnImagePlane =
        find.byKey(const ValueKey('gallery-return-image-plane'));

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: Center(
          child: Hero(
            tag: heroTag,
            flightShuttleBuilder: mediaGalleryHeroFlightShuttleBuilder,
            child: GestureDetector(
              key: const ValueKey('return-thumbnail'),
              onTap: () => navigatorKey.currentState!.push<void>(
                PageRouteBuilder<void>(
                  opaque: false,
                  transitionDuration: const Duration(milliseconds: 300),
                  pageBuilder: (_, __, ___) => Scaffold(
                    backgroundColor: Colors.black,
                    body: Center(
                      child: Hero(
                        tag: heroTag,
                        flightShuttleBuilder:
                            mediaGalleryHeroFlightShuttleBuilder,
                        child: const SizedBox(
                          key: ValueKey('return-gallery-image'),
                          width: 280,
                          height: 420,
                          child: ColoredBox(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const SizedBox(
                width: 80,
                height: 80,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(thumbnail);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(galleryImage, findsOneWidget);

    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(galleryImage, findsOneWidget);
    expect(thumbnail, findsNothing);
    // Non-image test children cannot provide capture geometry, so the shuttle
    // intentionally falls back to the active gallery child.
    expect(returnImagePlane, findsNothing);

    await tester.pump(const Duration(milliseconds: 230));
    expect(galleryImage, findsNothing);
    expect(thumbnail, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final pixels in [const Size(240, 120), const Size(120, 240)]) {
    for (final zoom in [1.0, 1.8]) {
      testWidgets(
          'return endpoints match ExtendedImage crop for $pixels zoom $zoom',
          (tester) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        // Patterned pixels reveal fit/crop errors unlike a solid fill.
        for (var x = 0; x < pixels.width; x += 10) {
          for (var y = 0; y < pixels.height; y += 10) {
            canvas.drawRect(
              Rect.fromLTWH(x.toDouble(), y.toDouble(), 10, 10),
              Paint()
                ..color = Color.fromARGB(255, x % 256, y % 256, (x + y) % 256),
            );
          }
        }
        final picture = recorder.endRecording();
        final image = (await tester.runAsync(() => picture.toImage(
              pixels.width.toInt(),
              pixels.height.toInt(),
            )))!;
        picture.dispose();

        final navigatorKey = GlobalKey<NavigatorState>();
        final sourceKey = GlobalKey();
        final galleryKey = GlobalKey();
        final boundaryKey = GlobalKey();
        final galleryBoundaryKey = GlobalKey();
        final tag = mediaGalleryHeroTag(
          Object(),
          0,
          thumbnailUsesCover: true,
        );

        await tester.pumpWidget(MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: Hero(
                  key: sourceKey,
                  tag: tag,
                  flightShuttleBuilder: mediaGalleryHeroFlightShuttleBuilder,
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ExtendedRawImage(
                        image: image,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));

        Future<List<int>> screenshot(GlobalKey key) async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final snapshot = await boundary.toImage(pixelRatio: 1);
          final data =
              await snapshot.toByteData(format: ui.ImageByteFormat.rawRgba);
          snapshot.dispose();
          return data!.buffer.asUint8List().toList();
        }

        final expectedTarget = await tester.runAsync(
          () => screenshot(boundaryKey),
        );
        navigatorKey.currentState!.push<void>(MediaGalleryRoute<void>(
          child: Scaffold(
            body: Center(
              child: Hero(
                key: galleryKey,
                tag: tag,
                flightShuttleBuilder: mediaGalleryHeroFlightShuttleBuilder,
                child: RepaintBoundary(
                  key: galleryBoundaryKey,
                  child: SizedBox(
                    width: 300,
                    height: 400,
                    child: ExtendedRawImage(
                      image: image,
                      fit: BoxFit.contain,
                      gestureDetails: GestureDetails(
                        totalScale: zoom,
                        offset: const Offset(-25, -35),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        final expectedStart = await tester.runAsync(
          () => screenshot(galleryBoundaryKey),
        );
        final startShuttle = mediaGalleryHeroFlightShuttleBuilder(
          galleryKey.currentContext!,
          const AlwaysStoppedAnimation(1),
          HeroFlightDirection.pop,
          galleryKey.currentContext!,
          sourceKey.currentContext!,
        );
        final endShuttle = mediaGalleryHeroFlightShuttleBuilder(
          galleryKey.currentContext!,
          const AlwaysStoppedAnimation(0),
          HeroFlightDirection.pop,
          galleryKey.currentContext!,
          sourceKey.currentContext!,
        );

        navigatorKey.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byKey(const ValueKey('gallery-return-image-plane')),
          findsOneWidget,
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 300,
                height: 400,
                child: startShuttle,
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(
          await tester.runAsync(() => screenshot(boundaryKey)),
          expectedStart,
          reason: 'the first flight frame preserves current zoom and pan',
        );

        await tester.pumpWidget(MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(width: 100, height: 100, child: endShuttle),
            ),
          ),
        ));
        await tester.pump();
        expect(
          await tester.runAsync(() => screenshot(boundaryKey)),
          expectedTarget,
          reason: 'the final flight frame matches the rounded cover thumbnail',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        image.dispose();
        expect(tester.takeException(), isNull);
      });
    }
  }
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
            home: const HomePage())));
    await tester.pumpAndSettle();
    expect(find.text('登录 X'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('登录 X'));
    await tester.pumpAndSettle();
    expect(find.text('Cookie 导入'), findsOneWidget);
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
  testWidgets('notifications route has its own visible page scaffold',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final controller = AppController();
    await tester.pumpWidget(ProviderScope(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      appControllerProvider.overrideWith((ref) => controller),
    ], child: const MaterialApp(home: NotificationsPage())));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('通知'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('history opens the post detail inside ReviewX', (tester) async {
    SharedPreferences.setMockInitialValues({
      'history_1': jsonEncode([
        {
          'id': '12345',
          'url': 'https://x.com/alice/status/12345',
          'title': '历史帖子',
          'author': 'alice',
          'time': '2026-10-05T00:00:00.000Z',
        }
      ])
    });
    final storage = await StorageService.init();
    final client = OfflineDetailClient()
      ..session = const TwitterSession('auth_token=stub; ct0=stub', '1');
    final controller = AppController(client: client);
    await tester.pumpWidget(ProviderScope(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      appControllerProvider.overrideWith((ref) => controller),
    ], child: const MaterialApp(home: HistoryPage())));
    await tester.tap(find.text('历史帖子'));
    await tester.pumpAndSettle();

    expect(find.text('帖子详情'), findsOneWidget);
    expect(find.text('模拟网络不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('post card keeps all six actions on one compact row',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    const post = SocialPost(
        id: 'six-actions',
        author: sampleUser,
        text: '六个操作',
        replies: 12345,
        reposts: 23456,
        likes: 34567,
        views: 45678);
    await tester.pumpWidget(ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: Scaffold(body: PostCard(post: post)))));
    await tester.pumpAndSettle();

    final row =
        tester.widget<Row>(find.byKey(const ValueKey('post-action-row')));
    final bounds =
        tester.getRect(find.byKey(const ValueKey('post-action-row')));
    expect(row.children, hasLength(6));
    expect(bounds.height, 40);
    for (final label in ['回复', '转发', '喜欢', '查看次数', '加入书签', '分享']) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('standard navigation follows system text scaling',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = AppTheme.lightTheme();
    const textScaler = TextScaler.linear(1.8);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        bottomNavigationBar: NavigationBarTheme(
          data: AppTheme.scaleNavigationBarTheme(
              theme.navigationBarTheme, textScaler),
          child: NavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: '首页'),
              NavigationDestination(icon: Icon(Icons.explore), label: '探索'),
              NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('设置'));
    expect(label.style?.fontSize, closeTo(21.6, 0.1));
    expect(
        tester.getSize(find.byType(NavigationBar)).height, closeTo(77.6, 0.1));
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
