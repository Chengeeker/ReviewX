import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:review_x/core/services/network_routing.dart';
import 'package:review_x/core/storage/storage_service.dart';
import 'package:review_x/presentation/network_settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('manual configuration rejects URLs, PAC injection and invalid ports',
      () {
    for (final host in [
      '',
      'http://localhost',
      'localhost:1234',
      'localhost; DIRECT',
      'localhost/path'
    ]) {
      expect(
          () =>
              NetworkConfig(mode: ConnectionMode.manual, host: host, port: 1234)
                  .validate(),
          throwsFormatException);
    }
    for (final port in [0, -1, 65536]) {
      expect(
          () => NetworkConfig(
                  mode: ConnectionMode.manual, host: 'localhost', port: port)
              .validate(),
          throwsFormatException);
    }
  });
  test('automatic exclusions and direct mode preserve route semantics', () {
    const system = SystemProxy(
        host: 'proxy.example',
        port: 8080,
        exclusions: ['*.local', 'localhost']);
    final auto = NetworkRouting(const NetworkConfig(), system);
    expect(auto.resolve(Uri.parse('https://api.x.com/')),
        'PROXY proxy.example:8080');
    expect(auto.resolve(Uri.parse('https://device.local/')), 'DIRECT');
    expect(auto.resolve(Uri.parse('https://not-local.example/')),
        'PROXY proxy.example:8080');
    expect(
        NetworkRouting(const NetworkConfig(mode: ConnectionMode.direct), system)
            .resolve(Uri.parse('https://api.x.com/')),
        'DIRECT');
  });
  test(
      'Dio uses configured HTTP proxy and never falls back to origin on failure',
      () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var origins = 0, proxies = 0;
    origin.listen((request) {
      origins++;
      request.response
        ..write('origin')
        ..close();
    });
    proxy.listen((request) {
      proxies++;
      request.response
        ..write('proxy')
        ..close();
    });
    final routing = NetworkRouting(
        NetworkConfig(
            mode: ConnectionMode.manual, host: '127.0.0.1', port: proxy.port),
        const SystemProxy());
    final url = 'http://127.0.0.1:${origin.port}/sample';
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        final dio =
            Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)));
        try {
          expect((await dio.get<String>(url)).data, 'proxy');
        } finally {
          dio.close(force: true);
        }
      }, routing);
      expect(proxies, 1);
      expect(origins, 0);
      await proxy.close(force: true);
      await HttpOverrides.runWithHttpOverrides(() async {
        final dio =
            Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)));
        try {
          await expectLater(dio.get<String>(url), throwsA(isA<DioException>()));
        } finally {
          dio.close(force: true);
        }
      }, routing);
      expect(origins, 0);
    } finally {
      await proxy.close(force: true);
      await origin.close(force: true);
    }
  });
  testWidgets('settings validate and persist a draft without applying it live',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final originalOverrides = HttpOverrides.current;
    await tester.pumpWidget(ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: NetworkSettingsPage())));
    await tester.tap(find.byType(DropdownButtonFormField<ConnectionMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动代理').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(storage.preferences.getString(NetworkConfig.key), isNull);
    await tester.enterText(find.byType(TextFormField).at(0), '127.0.0.1');
    await tester.enterText(find.byType(TextFormField).at(1), '8080');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final config = NetworkConfig.read(storage);
    expect(config.mode, ConnectionMode.manual);
    expect(config.host, '127.0.0.1');
    expect(config.port, 8080);
    expect(HttpOverrides.current, same(originalOverrides));
    expect(find.textContaining('已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
