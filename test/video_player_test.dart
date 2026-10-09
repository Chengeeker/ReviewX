import 'dart:async';
import 'dart:ui' as ui;
import 'package:extended_image/extended_image.dart';
import 'package:review_x/presentation/media_page.dart';
import 'package:review_x/core/storage/reading_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player/video_player.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/review_video_player.dart';
import 'package:review_x/presentation/compose_page.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/api/x_request_headers.dart';
import 'package:review_x/twitter/auth/app_controller.dart';
import 'package:review_x/twitter/auth/session.dart';
import 'package:review_x/twitter/models/social_models.dart';

const video = SocialMedia(
    preview: 'https://pbs.twimg.com/cover.jpg',
    video: 'https://video.twimg.com/720x1280/high.mp4',
    videoQualities: {
      '720p': 'https://video.twimg.com/720x1280/high.mp4',
      '360p': 'https://video.twimg.com/360x640/low.mp4'
    });
const videoForLoadingTest = SocialMedia(
    preview: 'https://pbs.twimg.com/loading-cover.jpg',
    video: 'https://video.twimg.com/720x1280/high.mp4',
    videoQualities: {
      '720p': 'https://video.twimg.com/720x1280/high.mp4',
      '360p': 'https://video.twimg.com/360x640/low.mp4'
    });
const post = SocialPost(
    id: '2',
    author: SocialUser(id: '1', name: '作者', handle: 'author'),
    text: '视频正文',
    media: [video],
    likes: 2000000,
    reposts: 10000,
    replies: 42);

class FakeVideoPlatform extends VideoPlayerPlatform {
  final urls = <String>[],
      headers = <Map<String, String>>[],
      disposed = <int>[],
      plays = <int>[],
      pauses = <int>[];
  final speeds = <double>[];
  final volumes = <double>[];
  final positions = <int, Duration>{};
  final events = <int, StreamController<VideoEvent>>{};
  bool autoInitialize = true;

  void emitInitialized(int playerId) {
    events[playerId]?.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 2),
        size: const Size(720, 1280)));
  }

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = urls.length + 1;
    urls.add(options.dataSource.uri!);
    headers.add(options.dataSource.httpHeaders);
    positions[id] = Duration.zero;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final controller = StreamController<VideoEvent>();
    events[playerId] = controller;
    controller.onListen = () {
      if (autoInitialize) emitInitialized(playerId);
    };
    return controller.stream;
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await events[playerId]?.close();
  }

  @override
  Future<void> play(int playerId) async {
    plays.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    pauses.add(playerId);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    speeds.add(speed);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId]!;
}

class VideoActionsClient extends TwitterClient {
  final operations = <String>[];
  Completer<Map<String, dynamic>>? delayedLike;
  @override
  Future<Map<String, dynamic>> call(
      String operation, Map<String, dynamic> variables) async {
    operations.add(operation);
    if (operation == 'FavoriteTweet') {
      return delayedLike?.future ?? {'favorite_tweet': 'Done'};
    }
    if (operation == 'CreateBookmark') return {'tweet_bookmark_put': 'Done'};
    if (operation == 'CreateRetweet') {
      return {
        'create_retweet': {
          'retweet_results': {
            'result': {'rest_id': '3'}
          }
        }
      };
    }
    throw const TwitterFailure('未配置的测试请求');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeVideoPlatform platform;
  late VideoActionsClient client;
  late AppController app;
  late StorageService storage;
  final nativeCalls = <String>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.init();
    platform = FakeVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    client = VideoActionsClient()
      ..session = const TwitterSession('auth_token=test; ct0=test', '1');
    app = AppController(client: client)..ready = true;
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.review.x/media'),
            (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'getPlayerLevels') {
        return {'brightness': 0.5, 'volume': 0.5, 'windowBrightness': -1.0};
      }
      return true;
    });
  });
  Widget player(
          {Key? key,
          bool active = true,
          double scale = 1,
          ReadingNotifier? readingNotifier,
          SocialMedia media = video}) =>
      ProviderScope(
          overrides: [
            appControllerProvider.overrideWith((ref) => app),
            storageServiceProvider.overrideWithValue(storage),
            if (readingNotifier != null)
              readingProvider.overrideWith((ref) => readingNotifier),
          ],
          child: MaterialApp(
              home: MediaQuery(
                  data: MediaQueryData(
                      size: const Size(360, 640),
                      textScaler: TextScaler.linear(scale)),
                  child: ReviewVideoPlayer(
                      key: key,
                      media: media,
                      active: active,
                      post: post,
                      author: 'author'))));

  testWidgets(
      'loading transport stays visible and video gallery uses one control layer',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    platform.autoInitialize = false;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 360, 640), Paint()..color = Colors.blue);
    final picture = recorder.endRecording();
    final decoded = await tester.runAsync(() => picture.toImage(360, 640));
    picture.dispose();
    final provider = ExtendedNetworkImageProvider(videoForLoadingTest.preview,
        cache: true, headers: XRequestHeaders.media);
    final key = await provider.obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: decoded!))));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          appControllerProvider.overrideWith((ref) => app),
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: MediaPage(
                    media: [videoForLoadingTest], index: 0, post: post)))));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'while loading');

    expect(platform.events, contains(1));
    expect(find.text('--:-- / --:--'), findsOneWidget);
    expect(find.byTooltip('视频加载中'), findsOneWidget);
    expect(find.byTooltip('横屏'), findsOneWidget);
    expect(find.byTooltip('加入书签'), findsOneWidget);
    expect(find.byType(VideoProgressIndicator), findsNothing);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    expect(find.byTooltip('保存视频'), findsOneWidget);
    expect(find.byTooltip('保存到相册'), findsNothing);

    platform.emitInitialized(1);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.byType(VideoProgressIndicator), findsOneWidget);
    expect(find.text('00:00 / 02:00'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'after initialization');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
      'default mute can be toggled and gestures adjust player gain, not system volume',
      (tester) async {
    final settings = ReadingNotifier(storage);
    await settings.set('defaultMutedVideo', true);
    expect(ReadingNotifier(storage).state['defaultMutedVideo'], isTrue);
    await tester.pumpWidget(player());
    await tester.pumpAndSettle();
    expect(platform.volumes.last, 0);
    expect(find.byTooltip('取消静音'), findsOneWidget);
    await tester.tap(find.byTooltip('取消静音'));
    await tester.pump();
    expect(platform.volumes.last, 1);
    expect(find.byTooltip('静音'), findsOneWidget);
    await tester.tap(find.byTooltip('静音'));
    await tester.pump();
    expect(platform.volumes.last, 0);
    expect(find.byTooltip('取消静音'), findsOneWidget);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.dragFrom(
        Offset(size.width * .8, size.height * .4), const Offset(0, 50));
    await tester.pump();
    expect(platform.volumes.last, greaterThan(.7));
    expect(platform.volumes.last, lessThan(1));
    expect(nativeCalls, isNot(contains('setVolume')));
    await tester.dragFrom(
        Offset(size.width * .8, size.height * .4), Offset(0, size.height));
    await tester.pump();
    expect(platform.volumes.last, 0);
    expect(find.byTooltip('取消静音'), findsOneWidget);
    await tester.tap(find.byTooltip('取消静音'));
    await tester.pump();
    expect(platform.volumes.last, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    settings.dispose();
  });

  testWidgets('loaded portrait and landscape images fit the centered viewport',
      (tester) async {
    for (final dimensions in [const Size(240, 900), const Size(900, 240)]) {
      final url = 'https://pbs.twimg.com/${dimensions.width}.jpg';
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
          .drawRect(Offset.zero & dimensions, Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      final decoded = await tester.runAsync(() =>
          picture.toImage(dimensions.width.toInt(), dimensions.height.toInt()));
      picture.dispose();
      final provider = ExtendedNetworkImageProvider(
          SocialMedia(preview: url).viewerImage(
              viewportWidth: 360, viewportHeight: 800, devicePixelRatio: 3),
          cache: true,
          headers: XRequestHeaders.media);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      PaintingBinding.instance.imageCache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: decoded!))));
      await tester.pumpWidget(ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: MaterialApp(
              home: MediaPage(
                  key: ValueKey(url),
                  media: [SocialMedia(preview: url)],
                  index: 0))));
      await tester.pumpAndSettle();
      final image = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
      final imageProvider = image.image as ExtendedNetworkImageProvider;
      expect(imageProvider.headers, XRequestHeaders.media);
      expect(imageProvider.headers!.containsKey('Cookie'), isFalse);
      final viewport = tester.getRect(find.byType(ExtendedImage));
      expect(image.width, viewport.width);
      expect(image.height, viewport.height);
      final state =
          (tester.state(find.byType(ExtendedImage)) as ExtendedImageState);
      expect(state.extendedImageInfo, isNotNull);
      final gestureState = tester
          .state<ExtendedImageGestureState>(find.byType(ExtendedImageGesture));
      final destination = GestureWidgetDelegateFromState.getRectFormState(
          Offset.zero & viewport.size, gestureState);
      expect(destination.center.dx, closeTo(viewport.width / 2, .01));
      expect(destination.center.dy, closeTo(viewport.height / 2, .01));
      expect(destination.width, lessThanOrEqualTo(viewport.width));
      expect(destination.height, lessThanOrEqualTo(viewport.height));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  });

  testWidgets(
      'Review controls preserve position when switching quality and pause on background',
      (tester) async {
    await tester.pumpWidget(player());
    await tester.pumpAndSettle();
    expect(platform.urls, [video.video]);
    expect(platform.headers.first, XRequestHeaders.media);
    expect(find.byTooltip('加入书签'), findsOneWidget);
    await tester.tap(find.text('1.0X'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5X'));
    await tester.pumpAndSettle();
    expect(platform.speeds.last, 1.5);
    platform.positions[1] = const Duration(seconds: 40);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('360p'));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(platform.urls.last, video.videoQualities['360p']);
    expect(platform.headers.last, XRequestHeaders.media);
    expect(platform.positions[2], const Duration(seconds: 40));
    expect(platform.disposed, contains(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(platform.pauses.last, 2);
    final plays = platform.plays.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.plays.length, plays);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(nativeCalls, contains('restorePlayerBrightness'));
  });

  testWidgets(
      'video quality preference respects balanced, high and data_saver settings',
      (tester) async {
    const multiQualityVideo = SocialMedia(
      preview: 'https://pbs.twimg.com/cover.jpg',
      video: 'https://video.twimg.com/1080x1920/1080p.mp4',
      videoQualities: {
        '1080p': 'https://video.twimg.com/1080x1920/1080p.mp4',
        '720p': 'https://video.twimg.com/720x1280/720p.mp4',
        '480p': 'https://video.twimg.com/480x854/480p.mp4',
        '360p': 'https://video.twimg.com/360x640/360p.mp4',
      },
    );

    final settings = ReadingNotifier(storage);

    // Default 'balanced' preference picks 720p
    await tester.pumpWidget(player(
        key: const ValueKey('balanced'),
        media: multiQualityVideo,
        readingNotifier: settings));
    await tester.pumpAndSettle();
    expect(platform.urls.last, multiQualityVideo.videoQualities['720p']);
    expect(platform.headers.last, XRequestHeaders.media);

    // 'high' preference picks 1080p
    await settings.set('videoQuality', 'high');
    app = AppController(client: client)..ready = true;
    await tester.pumpWidget(player(
        key: const ValueKey('high'),
        media: multiQualityVideo,
        readingNotifier: settings));
    await tester.pumpAndSettle();
    expect(platform.urls.last, multiQualityVideo.videoQualities['1080p']);

    // 'data_saver' preference picks 360p
    await settings.set('videoQuality', 'data_saver');
    app = AppController(client: client)..ready = true;
    await tester.pumpWidget(player(
        key: const ValueKey('data_saver'),
        media: multiQualityVideo,
        readingNotifier: settings));
    await tester.pumpAndSettle();
    expect(platform.urls.last, multiQualityVideo.videoQualities['360p']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'Review gestures seek, accelerate, change native levels and rotate',
      (tester) async {
    await tester.pumpWidget(player());
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(ReviewVideoPlayer));
    final right = Offset(size.width * 0.8, size.height * 0.3);
    platform.positions[1] = const Duration(seconds: 40);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tapAt(right);
    await tester.pump();
    expect(platform.positions[1], const Duration(seconds: 50));
    final press = await tester.startGesture(right);
    await tester.pump(const Duration(milliseconds: 600));
    expect(platform.speeds.last, 2);
    await press.up();
    await tester.pump();
    expect(platform.speeds.last, 1);
    await tester.dragFrom(
        Offset(size.width * 0.2, size.height * 0.4), const Offset(0, -90));
    await tester.pump();
    expect(nativeCalls, contains('setBrightness'));
    await tester.dragFrom(
        Offset(size.width * 0.8, size.height * 0.4), const Offset(0, -90));
    await tester.pump();
    expect(nativeCalls, isNot(contains('setVolume')));
    expect(platform.volumes.last, greaterThan(0));
    await tester.tap(find.byTooltip('横屏'));
    await tester.pump();
    expect(find.byTooltip('竖屏'), findsOneWidget);
    await tester.tap(find.byTooltip('竖屏'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('only active media allocates a controller; leaving releases it',
      (tester) async {
    await tester.pumpWidget(player(active: false));
    await tester.pumpAndSettle();
    expect(platform.urls, isEmpty);
    await tester.pumpWidget(player());
    await tester.pumpAndSettle();
    expect(platform.urls.length, 1);
    await tester.pumpWidget(player(active: false));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    expect(platform.disposed, [1]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'player interactions share existing Twitter state and use bookmarks',
      (tester) async {
    await tester.pumpWidget(player());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('喜欢'));
    await tester.pumpAndSettle();
    expect(app.effective(post).liked, isTrue);
    expect(find.byTooltip('取消喜欢'), findsOneWidget);
    await tester.tap(find.byTooltip('转发'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('加入书签'));
    await tester.pumpAndSettle();
    expect(app.effective(post).reposted, isTrue);
    expect(app.effective(post).bookmarked, isTrue);
    expect(client.operations,
        ['FavoriteTweet', 'CreateRetweet', 'CreateBookmark']);
    await tester.tap(find.byTooltip('评论'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发表评论'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePage), findsOneWidget);
    expect(find.text('回复 @author'), findsOneWidget);
    expect(platform.pauses, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('pending and uncertain actions cannot be sent again',
      (tester) async {
    client.delayedLike = Completer();
    await tester.pumpWidget(player());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('喜欢'));
    await tester.pump();
    final button = tester.widget<TextButton>(find.descendant(
        of: find.byTooltip('取消喜欢'), matching: find.byType(TextButton)));
    expect(button.onPressed, isNull);
    client.delayedLike!
        .completeError(const TwitterFailure('操作结果待核对', uncertain: true));
    await tester.pumpAndSettle();
    expect(app.effective(post).liked, isFalse);
    expect(app.isUncertain(post.id), isTrue);
    expect(client.operations, ['FavoriteTweet']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('normal phone transport keeps fullscreen on the playback row',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(player());
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byTooltip('横屏')).dy,
        closeTo(tester.getCenter(find.text('1.0X')).dy, 1));
    expect(tester.getCenter(find.byTooltip('横屏')).dy,
        closeTo(tester.getCenter(find.byTooltip('暂停')).dy, 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('controls fit narrow portrait and landscape with large text',
      (tester) async {
    for (final size in [const Size(320, 640), const Size(640, 320)]) {
      app = AppController(client: client)..ready = true;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(player(scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  test('Twitter MP4 qualities use real variants and survive cache round-trip',
      () {
    final media = SocialMedia.parse({
      'media_url_https': video.preview,
      'video_info': {
        'variants': [
          {
            'content_type': 'video/mp4',
            'bitrate': 1000,
            'url': video.videoQualities['360p']
          },
          {'content_type': 'video/mp4', 'bitrate': 4000, 'url': video.video},
          {
            'content_type': 'application/x-mpegURL',
            'url': 'https://video.twimg.com/a.m3u8'
          },
          {
            'content_type': 'video/mp4',
            'bitrate': 9000,
            'url': 'https://other.example/a.mp4'
          },
        ]
      }
    })!;
    expect(media.video, video.video);
    expect(media.videoQualities.keys, ['720p', '360p']);
    expect(SocialMedia.fromCacheJson(media.toCacheJson())!.videoQualities,
        media.videoQualities);
    final legacy = SocialMedia.fromCacheJson(
        {'preview': video.preview, 'video': video.video});
    expect(legacy!.videoQualities, isEmpty);
  });
}
