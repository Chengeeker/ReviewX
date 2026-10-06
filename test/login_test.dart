import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/presentation/login_page.dart';
import 'package:review_x/twitter/api/twitter_client.dart';
import 'package:review_x/twitter/auth/app_controller.dart';
import 'package:review_x/twitter/auth/session.dart';

class PendingIdentityClient extends TwitterClient {
  final identity = Completer<String?>();
  @override
  Future<String?> initialUserId(String cookie) => identity.future;
}

class CookieLoginController extends AppController {
  final attempts = <String>[];
  Completer<void>? pending;
  Object? failure;
  var webAttempts = 0;
  var webResult = false;

  @override
  Future<void> login(String rawCookie) async {
    attempts.add(rawCookie);
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<bool> loginWithWeb() async {
    webAttempts++;
    return webResult;
  }
}

void main() {
  test('X web cookies are normalized and unrelated cookies are discarded', () {
    expect(
      TwitterSession.fromCookies({
        'auth_token': 'session',
        'ct0': 'csrf',
        'twid': 'u%3D123',
        'gt': 'guest-token',
        'guest_id': 'unrelated',
      }),
      'auth_token=session; ct0=csrf; twid=u%3D123; gt=guest-token',
    );
    expect(
      () => TwitterSession.fromCookies({'auth_token': 'bad;ct0=injected'}),
      throwsFormatException,
    );
  });

  test('overlapping login cannot report success while identity is pending',
      () async {
    final client = PendingIdentityClient();
    final controller = AppController(client: client);
    final first = controller.login('auth_token=test-only; ct0=test-only');
    final firstFailure = expectLater(first, throwsA(isA<TwitterFailure>()));
    expect(controller.busy, isTrue);
    await expectLater(
      controller.login('auth_token=second-test-only; ct0=test-only'),
      throwsA(isA<TwitterFailure>()),
    );
    expect(controller.loggedIn, isFalse);
    expect(controller.busy, isTrue);
    client.identity.complete(null);
    await firstFailure;
    expect(controller.busy, isFalse);
    expect(controller.loggedIn, isFalse);
    controller.dispose();
  });

  testWidgets('ReviewX login keeps an X entry and explicit Cookie import',
      (tester) async {
    final controller = CookieLoginController()..pending = Completer<void>();
    await tester.pumpWidget(ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: LoginPage()),
    ));
    expect(find.text('账号登录'), findsOneWidget);
    expect(find.text('Cookie 导入'), findsOneWidget);
    expect(find.text('使用 X 官方页面登录'), findsOneWidget);
    expect(find.byKey(const Key('loginIdentifier')), findsNothing);
    expect(find.byKey(const Key('loginPassword')), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Cookie 导入'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cookieField')), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('cookieField')))
            .obscureText,
        isTrue);
    await tester.enterText(
        find.byKey(const Key('cookieField')), 'auth_token=fake; ct0=fake');
    await tester.tap(find.text('验证并登录'));
    await tester.pump();
    expect(controller.attempts, ['auth_token=fake; ct0=fake']);
    controller.failure = const TwitterFailure('会话已过期');
    controller.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('会话已过期'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('cookieField')))
            .controller!
            .text,
        'auth_token=fake; ct0=fake');
    expect(find.text('验证并登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cookie error does not reveal credential details',
      (tester) async {
    final controller = CookieLoginController()
      ..failure = Exception('auth_token=private-test-value');
    await tester.pumpWidget(ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: LoginPage()),
    ));
    await tester.tap(find.widgetWithText(TextButton, 'Cookie 导入'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('cookieField')), 'auth_token=fake; ct0=fake');
    await tester.tap(find.text('验证并登录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('private-test-value'), findsNothing);
    expect(find.text('登录验证失败，请检查网络或安全存储后重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verified Cookie clears input and closes login route',
      (tester) async {
    final controller = CookieLoginController();
    await tester.pumpWidget(ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => controller)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LoginPage())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cookie 导入'));
    await tester.pumpAndSettle();
    final input = tester
        .widget<TextField>(find.byKey(const Key('cookieField')))
        .controller!;
    await tester.enterText(
        find.byKey(const Key('cookieField')), 'auth_token=fake; ct0=fake');
    await tester.tap(find.text('验证并登录'));
    await tester.pump();
    expect(input.text, isEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('X login opens directly without collecting credentials',
      (tester) async {
    final controller = CookieLoginController();
    await tester.pumpWidget(ProviderScope(
      overrides: [appControllerProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: LoginPage()),
    ));
    expect(find.byKey(const Key('loginIdentifier')), findsNothing);
    expect(find.byKey(const Key('loginPassword')), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '前往 X 登录'));
    await tester.pumpAndSettle();
    expect(controller.webAttempts, 1);
    expect(find.text('Cookie 导入'), findsOneWidget);
  });
}
