import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/settings_pane.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/app_controller.dart';
import 'package:review_x/twitter/auth/session.dart';

void main() {
  testWidgets(
      'export copies only on request and invalidates an old account sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    const fakeCookie = 'auth_token=fake-test-token; ct0=fake-test-csrf';
    final client = TwitterClient()
      ..session = const TwitterSession(fakeCookie, '1');
    final controller = AppController(client: client);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Clipboard.hasStrings') return {'value': false};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(ProviderScope(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      appControllerProvider.overrideWith((_) => controller),
    ], child: const MaterialApp(home: Scaffold(body: SettingsPane()))));
    await tester.ensureVisible(find.text('导出 Cookie'));
    await tester.tap(find.text('导出 Cookie'));
    await tester.pumpAndSettle();
    expect(copied, isNull);
    expect(find.text(fakeCookie), findsOneWidget);
    await tester.tap(find.text('复制全部'));
    await tester.pumpAndSettle();
    expect(copied, fakeCookie);
    copied = null;
    await tester.tap(find.text('导出 Cookie'));
    await tester.pumpAndSettle();
    client.session = null;
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text(fakeCookie), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.ancestor(
                of: find.text('复制全部'),
                matching:
                    find.byWidgetPredicate((widget) => widget is FilledButton)))
            .onPressed,
        isNull);
    expect(copied, isNull);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('登录 X 账号'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
