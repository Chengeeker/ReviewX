import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/article_page.dart';
import 'package:review_x/presentation/media_page.dart';
import 'package:review_x/presentation/post_card.dart';
import 'package:review_x/twitter/api/x_request_headers.dart';
import 'package:review_x/twitter/models/social_models.dart';

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

const _media = [
  SocialMedia(
      preview: 'https://reentry.invalid/one.png', width: 800, height: 600),
  SocialMedia(
      preview: 'https://reentry.invalid/two.png', width: 800, height: 600),
];
const _post = SocialPost(
    id: 'reentry',
    author: SocialUser(id: '1', name: 'ReviewX', handle: 'reviewx'),
    text: 'Image card',
    media: _media);

Future<void> _cacheImages(WidgetTester tester) async {
  final image = (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(800, 600);
    picture.dispose();
    return image;
  }))!;
  final keys = <Object>[];
  for (final item in _media) {
    for (final url in [item.preview, item.original]) {
      for (final width in <int?>[null, 160, 185]) {
        final provider = ExtendedImage.network(url,
                cache: true, cacheWidth: width, headers: XRequestHeaders.media)
            .image;
        final key = await provider.obtainKey(ImageConfiguration.empty);
        keys.add(key);
        imageCache.putIfAbsent(
            key,
            () => OneFrameImageStreamCompleter(
                Future.value(ImageInfo(image: image.clone()))));
      }
    }
  }
  image.dispose();
  addTearDown(() {
    for (final key in keys) {
      imageCache.evict(key);
    }
  });
}

Future<void> _expectCenteredFlight(WidgetTester tester) async {
  final plane = find.byKey(const ValueKey('gallery-return-image-plane'));
  expect(plane, findsOneWidget);
  final size = tester.getSize(plane);
  final painter = tester.widget<CustomPaint>(plane).painter!;
  final pixel = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    picture.dispose();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = ((size.height ~/ 2) * image.width + size.width ~/ 2) * 4;
    final pixel = data.buffer.asUint8List().sublist(offset, offset + 4);
    image.dispose();
    return pixel;
  });
  expect(pixel, [33, 150, 243, 255],
      reason: 'reversing again must keep pixels centered in the flying image');
}

void main() {
  for (final article in [false, true]) {
    for (final openedFor in [50, 350]) {
      testWidgets(
          '${article ? 'article' : 'post'} image can reopen during return ($openedFor ms)',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final storage = await StorageService.init();
        await _cacheImages(tester);
        final navigator = GlobalKey<NavigatorState>();
        final routes = _Routes();
        var articleOpens = 0;
        await tester.pumpWidget(ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [routes],
            home: Scaffold(
                body: article
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => articleOpens++,
                        child: const ArticleMedia(
                            media: _media, author: 'reviewx'))
                    : const PostCard(post: _post)),
          ),
        ));
        await tester.pumpAndSettle();
        final point = tester.getCenter(article
            ? find.byType(Hero).first
            : find.byKey(const ValueKey('post-media-reentry-0')));
        await tester.tapAt(point);
        await tester.pump();
        await tester.pump(Duration(milliseconds: openedFor));
        for (final cycle in [2, 3, 4]) {
          navigator.currentState!.pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 10));
          await tester.tapAt(point);
          await tester.pump();
          expect(articleOpens, 0);
          expect(routes.pushed.skip(1).every((r) => r is MediaGalleryRoute),
              isTrue,
              reason: 'an image tap must not reach the enclosing article/post');
          expect(routes.pushed.length, cycle + 1);
          await tester.pump(const Duration(milliseconds: 50));
          if (!article && openedFor == 350) {
            for (final step in [1, 16, 33]) {
              await tester.pump(Duration(milliseconds: step));
              await _expectCenteredFlight(tester);
            }
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await tester.tapAt(point);
        await tester.pump();
        expect(articleOpens, 0);
        expect(routes.pushed.length, 6);
        expect(
            routes.pushed.skip(1).every((r) => r is MediaGalleryRoute), isTrue);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
