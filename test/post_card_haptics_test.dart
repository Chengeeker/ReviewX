import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/core/utils/haptic_feedback_util.dart';
import 'package:review_x/presentation/post_card.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/app_controller.dart';
import 'package:review_x/twitter/models/social_models.dart';

void main() {
  testWidgets('scrolling from a post does not trigger press haptics',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final controller = AppController(client: TwitterClient());
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        appControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: const HapticSplashFactory()),
        home: Scaffold(
          body: ListView(
            children: List.generate(
              6,
              (index) => PostCard(
                post: SocialPost(
                  id: 'post-$index',
                  author: const SocialUser(
                      id: 'author', name: 'Author', handle: 'author'),
                  text: '帖子内容 $index',
                ),
              ),
            ),
          ),
        ),
      ),
    ));

    final body = find.text('帖子内容 0');
    final gesture = await tester.startGesture(tester.getCenter(body));
    await tester.pump(const Duration(milliseconds: 80));
    expect(haptics, isEmpty);
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(haptics, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
