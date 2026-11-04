import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/services/settings_backup.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/webdav_backup_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cookie = 'auth_token=SECRET_TOKEN; ct0=SECRET_CSRF; twid=u%3D1';
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 2,
      'history_1': '[]',
      'search_history_1': '["hello"]',
      'network_config': '{"mode":"direct","host":"","port":0}',
      'cookie': 'UNEXPECTED_SECRET',
      'token': 'UNEXPECTED_SECRET',
    });
    FlutterSecureStorage.setMockInitialValues({
      'twitter_session_v1': jsonEncode({'cookie': cookie, 'userId': '1'}),
      'webdav_config': jsonEncode({
        'url': 'https://example.com/dav/',
        'user': 'user',
        'password': 'SECRET_PASSWORD',
        'directory': 'ReviewX'
      }),
    });
  });

  test(
      'safe backup excludes credentials and restores local data without replacing login',
      () async {
    final backup = SettingsBackup(await StorageService.init());
    final safe = await backup.exportAll();
    final encoded = jsonEncode(safe);
    expect(encoded, isNot(contains('SECRET')));
    expect(safe['backup_mode'], 'safe');
    expect(safe['local']['search_history_1'], '["hello"]');
    await backup.storage.preferences.setString('search_history_1', '[]');
    await backup.restore(safe);
    expect(
        backup.storage.preferences.getString('search_history_1'), '["hello"]');
    expect(await backup.secure.read(key: 'twitter_session_v1'),
        contains('SECRET_TOKEN'));
    expect(await backup.secure.read(key: 'webdav_config'),
        contains('SECRET_PASSWORD'));
  });

  test(
      'full backup requires explicit restore opt-in and restores secure credentials',
      () async {
    final backup = SettingsBackup(await StorageService.init());
    final full = await backup.exportAll(includeCredentials: true);
    expect(jsonEncode(full), contains('SECRET_TOKEN'));
    expect(jsonEncode(full), contains('SECRET_PASSWORD'));
    await expectLater(backup.restore(full), throwsFormatException);
    await backup.secure.delete(key: 'twitter_session_v1');
    await backup.secure
        .write(key: 'webdav_config', value: '{"password":"local"}');
    await backup.restore(full, allowCredentials: true);
    expect(await backup.secure.read(key: 'twitter_session_v1'),
        contains('SECRET_TOKEN'));
    expect(await backup.secure.read(key: 'webdav_config'),
        contains('SECRET_PASSWORD'));
    full['credentials']['session']['userId'] = '2';
    await expectLater(
        backup.restore(full, allowCredentials: true), throwsFormatException);
  });

  testWidgets(
      'WebDAV layout has Review cards, two backup choices and four configuration fields',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = await StorageService.init();
    await tester.pumpWidget(ProviderScope(overrides: [
      storageServiceProvider.overrideWithValue(storage),
    ], child: const MaterialApp(home: BackupSettingsPage())));
    await tester.pumpAndSettle();
    expect(find.text('全量安全备份'), findsOneWidget);
    expect(find.text('全量备份'), findsOneWidget);
    expect(
        tester
            .widget<RadioListTile<bool>>(find.byType(RadioListTile<bool>).first)
            .value,
        false);
    await tester.tap(find.text('全量备份'));
    await tester.pump();
    final scrollable = find
        .descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('备份文件夹名称'), 250,
        scrollable: scrollable);
    expect(find.text('WebDAV 服务器配置'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('从云端恢复备份'), 250,
        scrollable: scrollable);
    expect(find.text('立即备份到云端'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
