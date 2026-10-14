import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:review_x/presentation/media_page.dart';
import 'package:review_x/twitter/models/social_models.dart';

void main() {
  testWidgets('main gallery stays still while thumbnail drag is held',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final media = List.generate(
      18,
      (index) => SocialMedia(
        preview: 'https://pbs.twimg.com/gallery-$index.jpg',
        width: 800,
        height: 600,
      ),
    );
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MediaGalleryRoute<void>(
                    child: MediaPage(media: media, index: 0),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
    final thumbnails = tester.widget<PageView>(
      find.descendant(of: strip, matching: find.byType(PageView)),
    );
    final main = tester.widget<ExtendedImageGesturePageView>(
      find.byType(ExtendedImageGesturePageView),
    );
    final gesture = await tester.startGesture(tester.getCenter(strip));
    final pageExtent = thumbnails.controller!.position.viewportDimension * .16;
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(Offset(-pageExtent * .175, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    final heldThumbnailPage = thumbnails.controller!.page!;
    final heldMainPage = main.controller.page!;
    expect(
      tester
          .widget<ExtendedImageGesturePageView>(
            find.byType(ExtendedImageGesturePageView),
          )
          .pageSnapping,
      isFalse,
    );
    expect(heldThumbnailPage, inInclusiveRange(.4, .6));
    expect(heldMainPage, closeTo(heldThumbnailPage, .02));

    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(thumbnails.controller!.page, closeTo(heldThumbnailPage, .001));
      expect(main.controller.page, closeTo(heldMainPage, .02));
    }

    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final finalIndex = thumbnails.controller!.page!.round();
    expect(thumbnails.controller!.page, closeTo(finalIndex.toDouble(), .02));
    expect(main.controller.page, closeTo(finalIndex.toDouble(), .02));
    expect(
      tester
          .widget<ExtendedImageGesturePageView>(
            find.byType(ExtendedImageGesturePageView),
          )
          .pageSnapping,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
