import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/core/utils/haptic_feedback_util.dart';
import 'package:review_x/presentation/media_page.dart';
import 'package:review_x/twitter/api/x_request_headers.dart';
import 'package:review_x/twitter/models/social_models.dart';

class _DecodedImageStream extends ImageStreamCompleter {
  void addFrame(ui.Image image) => setImage(ImageInfo(image: image));
}

Future<void> _cacheImages(WidgetTester tester, List<String> urls) async {
  final image = (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(120, 240);
    picture.dispose();
    return image;
  }))!;
  final providers = urls
      .map((url) => ExtendedNetworkImageProvider(
            url,
            cache: true,
            headers: XRequestHeaders.media,
          ))
      .toList();
  for (final provider in providers) {
    final stream = _DecodedImageStream()..addFrame(image.clone());
    imageCache.putIfAbsent(provider, () => stream);
  }
  addTearDown(() {
    for (final provider in providers) {
      imageCache.evict(provider);
    }
    image.dispose();
  });
}

void main() {
  late StorageService storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.init();
  });
  testWidgets('decoded image fast swipe and Hero overlay stay error-free',
      (tester) async {
    final haptics = <Object?>[];
    HapticFeedbackUtil.isEnabled = true;
    HapticFeedbackUtil.resetForTesting();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      HapticFeedbackUtil.resetForTesting();
    });
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const media = [
      SocialMedia(preview: 'https://gallery-test.invalid/one.png'),
      SocialMedia(preview: 'https://gallery-test.invalid/two.png'),
    ];
    await _cacheImages(tester, media.map((item) => item.preview).toList());
    final scope = Object();
    final heroTag = mediaGalleryHeroTag(scope, 0);

    await tester.pumpWidget(ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
          home: Builder(builder: (context) {
            return Scaffold(
              body: Center(
                child: GestureDetector(
                  key: const ValueKey('open-gallery'),
                  onTap: () => Navigator.of(context).push<void>(
                    MediaGalleryRoute<void>(
                      child:
                          MediaPage(media: media, index: 0, heroScope: scope),
                    ),
                  ),
                  child: Hero(
                    tag: heroTag,
                    flightShuttleBuilder: mediaGalleryHeroFlightShuttleBuilder,
                    child: const SizedBox(
                      width: 120,
                      height: 80,
                      child: ColoredBox(color: Colors.blue),
                    ),
                  ),
                ),
              ),
            );
          }),
        )));

    await tester.tap(find.byKey(const ValueKey('open-gallery')));
    await tester.pump();
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
    }

    final pager = find.byType(ExtendedImageGesturePageView);
    final controller =
        tester.widget<ExtendedImageGesturePageView>(pager).controller;
    final drag = await tester.startGesture(tester.getCenter(pager));
    for (final distance in [-40.0, -160.0, -160.0]) {
      await drag.moveBy(Offset(distance, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.page, greaterThan(0));
    await drag.moveBy(const Offset(-400, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.page, greaterThan(.5));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.page, greaterThan(.5));
    expect(haptics, isEmpty, reason: 'main image swipes stay haptic-free');

    final galleryModes = tester.widgetList<HeroMode>(find.byType(HeroMode));
    final selectedHero = galleryModes
        .where((mode) => mode.child is Hero)
        .firstWhere((mode) =>
            (mode.child as Hero).tag == mediaGalleryHeroTag(scope, 1));
    expect(selectedHero.enabled, isTrue);
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
