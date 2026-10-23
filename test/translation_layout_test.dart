import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/services/google_translate_service.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/post_card.dart';
import 'package:review_x/twitter/models/social_models.dart';

class TranslationTransport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<dynamic>? stream,
          Future<void>? cancelFuture) async =>
      ResponseBody.fromString(
          jsonEncode([
            [
              ["缓存中的中文译文"]
            ]
          ]),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('recreated translated cards use cached text on their first frame',
      (tester) async {
    final client = GoogleTranslateService.clientForTesting;
    final oldAdapter = client.httpClientAdapter;
    client.httpClientAdapter = TranslationTransport();
    addTearDown(() => client.httpClientAdapter = oldAdapter);
    const original = 'A long foreign post with different line wrapping. '
        'The original and translated paragraphs have different heights.';
    await tester.runAsync(() => GoogleTranslateService.translate(original));
    SharedPreferences.setMockInitialValues({
      'reading_settings': jsonEncode({'grokAutoTranslate': true}),
    });
    final storage = await StorageService.init();
    const post = SocialPost(
        id: 'cached-translation-layout',
        author: SocialUser(id: 'a', name: 'Author', handle: 'author'),
        text: original);
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: const MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(child: PostCard(post: post))))));
      expect(
          find.textContaining('缓存中的中文译文', findRichText: true), findsOneWidget);
      final firstHeight = tester.getSize(find.byType(PostCard)).height;
      await tester.pump();
      expect(tester.getSize(find.byType(PostCard)).height, firstHeight);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
