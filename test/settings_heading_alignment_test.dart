import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/core/theme/app_theme.dart';
import 'package:review_x/presentation/settings_pane.dart';
import 'package:review_x/presentation/theme_settings_page.dart';
import 'package:review_x/presentation/cache_management_page.dart';
import 'package:review_x/twitter/auth/app_controller.dart';

void main() {
  testWidgets('section headings align with card content in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const cacheChannel = MethodChannel('com.review.x/cache');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(cacheChannel, (_) async => <String, int>{});
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(cacheChannel, null));
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final pages = <(Widget, String, IconData)>[
      (const Scaffold(body: SettingsPane()), '偏好与功能', Icons.palette_outlined),
      (const ThemeSettingsPage(), '色彩方案', Icons.auto_awesome_outlined),
      (const CacheManagementPage(), '自动清理规则', Icons.auto_delete_outlined),
    ];
    for (final brightness in Brightness.values) {
      for (final (page, heading, icon) in pages) {
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            appControllerProvider.overrideWith((ref) => AppController()),
          ],
          child: MaterialApp(
            theme: brightness == Brightness.light
                ? AppTheme.lightTheme()
                : AppTheme.darkTheme(),
            home: page,
          ),
        ));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byIcon(icon), 200,
            scrollable: find.byType(Scrollable).first);
        expect(tester.getTopLeft(find.text(heading)).dx,
            closeTo(tester.getTopLeft(find.byIcon(icon)).dx, 0.01),
            reason: '$heading in $brightness must align with the content');
        expect(tester.takeException(), isNull);
      }
    }
  });
}
