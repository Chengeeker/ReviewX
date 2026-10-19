import 'dart:ui' as ui;
import 'package:extended_image/extended_image.dart';
import 'package:review_x/twitter/api/x_request_headers.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/reading_settings.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/article_page.dart';
import 'package:review_x/presentation/post_card.dart';
import 'package:review_x/presentation/reading_style_preview.dart';
import 'package:review_x/presentation/settings_pages.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/app_controller.dart';

void main() {
  test(
      'legacy media folder choices migrate to both types without losing overrides',
      () {
    final old = validatedReading({'storageFolder': 'me'});
    expect(old['imageStorageFolder'], 'me');
    expect(old['videoStorageFolder'], 'me');
    final split = validatedReading({
      'storageFolder': 'author',
      'imageStorageFolder': 'default',
      'videoStorageFolder': '../invalid',
    });
    expect(split['imageStorageFolder'], 'default');
    expect(split['videoStorageFolder'], 'author');
    expect(validatedReading(split), split);
  });

  Future<StorageService> pumpSettings(WidgetTester tester, Widget page,
      {double textScale = 1}) async {
    SharedPreferences.setMockInitialValues({
      'reading_settings': jsonEncode({'storageFolder': 'me'}),
    });
    final storage = await StorageService.init();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        appControllerProvider
            .overrideWith((ref) => AppController(client: TwitterClient())),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: page,
      ),
    ));
    return storage;
  }

  testWidgets('Review-style path sheet saves only the selected media type',
      (tester) async {
    final storage = await pumpSettings(tester, const StorageSettingsPage());
    expect(find.text('图片存储路径'), findsOneWidget);
    expect(find.text('视频存储路径'), findsOneWidget);
    await tester.tap(find.text('图片存储路径'));
    await tester.pumpAndSettle();
    expect(find.byType(RadioListTile<String>), findsNWidgets(3));
    await tester.tap(find.text('按作者账号归类'));
    await tester.pumpAndSettle();
    final saved = validatedReading(
        jsonDecode(storage.preferences.getString('reading_settings')!));
    expect(saved['imageStorageFolder'], 'author');
    expect(saved['videoStorageFolder'], 'me');
    expect(find.text('Pictures/ReviewX/帖子作者账号/'), findsOneWidget);
    expect(find.text('Movies/ReviewX/MyProfile/'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(400, 800), const Size(800, 400)]) {
    testWidgets(
        'half-height preview stays fixed and reflects live edits at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(120, 50)))!;
      picture.dispose();
      final provider = ExtendedNetworkImageProvider(
          'https://picsum.photos/id/1015/1200/500',
          cache: true,
          headers: XRequestHeaders.media);
      imageCache.putIfAbsent(
          provider,
          () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: image))));
      addTearDown(() => imageCache.evict(provider));
      await pumpSettings(tester, const ReadingSettingsPage(), textScale: 1.4);
      final preview = find.byType(ReadingStylePreview);
      final controls =
          find.byKey(const ValueKey('reading-style-settings-scroll'));
      expect(tester.getSize(preview).height,
          lessThanOrEqualTo(tester.getSize(controls).height));
      final position = tester.getTopLeft(preview);
      await tester.drag(controls, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(preview), position);
      final container = ProviderScope.containerOf(tester.element(preview));
      container.read(readingProvider.notifier).preview('fontSize', 23.0);
      container.read(readingProvider.notifier).preview('imageRadius', 24.0);
      container.read(readingProvider.notifier).preview('largeImages', false);
      container
          .read(readingProvider.notifier)
          .preview('grokAutoTranslate', true);
      await tester.pump();
      expect(
          tester
              .widget<RichContentText>(find.byType(RichContentText).first)
              .style
              .fontSize,
          23);
      final grid =
          find.descendant(of: preview, matching: find.byType(MediaGrid));
      expect(grid, findsOneWidget);
      expect(
          find.descendant(
              of: preview, matching: find.byType(SingleChildScrollView)),
          findsNothing);
      final card =
          find.descendant(of: preview, matching: find.byType(PostCard));
      final cardPosition = tester.getTopLeft(card);
      final settingsOffset = tester
          .state<ScrollableState>(find
              .descendant(of: controls, matching: find.byType(Scrollable))
              .first)
          .position
          .pixels;
      await tester.drag(preview, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(card), cardPosition);
      expect(
          tester
              .state<ScrollableState>(find
                  .descendant(of: controls, matching: find.byType(Scrollable))
                  .first)
              .position
              .pixels,
          settingsOffset);
      final clip = tester.widget<ClipRRect>(
          find.descendant(of: grid, matching: find.byType(ClipRRect)).first);
      expect(clip.borderRadius, BorderRadius.circular(24));
      final layout = tester.widget<GridView>(
          find.descendant(of: grid, matching: find.byType(GridView)));
      expect(
          (layout.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .childAspectRatio,
          1.4);
      expect(find.textContaining('记录生活中的片刻'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
