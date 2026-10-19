import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/core/services/link_opener.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Launcher extends UrlLauncherPlatform {
  @override
  get linkDelegate => null;

  final calls = <(String, LaunchOptions)>[];
  bool succeeds = true;
  bool throwsError = false;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url, options));
    if (throwsError) throw PlatformException(code: 'NO_ACTIVITY');
    return succeeds;
  }
}

void main() {
  late _Launcher launcher;
  late UrlLauncherPlatform original;
  setUp(() {
    original = UrlLauncherPlatform.instance;
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
  });
  tearDown(() => UrlLauncherPlatform.instance = original);

  Future<void> pumpLink(WidgetTester tester, String url) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      return TextButton(
          onPressed: () => openAppLink(context, Uri.parse(url)),
          child: const Text('打开链接'));
    }))));
    await tester.tap(find.text('打开链接'));
    await tester.pumpAndSettle();
  }

  for (final scheme in ['https', 'http']) {
    testWidgets('$scheme links use the in-app browser without app headers',
        (tester) async {
      await pumpLink(tester, '$scheme://example.com/article');
      expect(launcher.calls, hasLength(1));
      final options = launcher.calls.single.$2;
      expect(options.mode, PreferredLaunchMode.inAppBrowserView);
      expect(options.browserConfiguration.showTitle, isTrue);
      expect(options.webViewConfiguration.headers, isEmpty);
    });
  }

  testWidgets('non-web URLs and embedded credentials are rejected',
      (tester) async {
    for (final url in [
      'javascript:alert(1)',
      'https://user:secret@example.com'
    ]) {
      await pumpLink(tester, url);
      expect(launcher.calls, isEmpty);
      expect(find.text('不支持的网页链接'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final throwsError in [false, true]) {
    testWidgets(
        'in-app failure offers external launch only after a tap ($throwsError)',
        (tester) async {
      launcher.succeeds = false;
      launcher.throwsError = throwsError;
      await pumpLink(tester, 'https://example.com');
      expect(launcher.calls, hasLength(1));
      expect(find.text('无法在应用内打开此网页'), findsOneWidget);
      launcher.succeeds = true;
      launcher.throwsError = false;
      await tester.tap(find.text('外部打开'));
      await tester.pumpAndSettle();
      expect(launcher.calls, hasLength(2));
      expect(
          launcher.calls.last.$2.mode, PreferredLaunchMode.externalApplication);
    });
  }
}
