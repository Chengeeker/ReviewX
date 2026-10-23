import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/core/services/diagnostic_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagnostic export redacts secrets and excludes exception text',
      () async {
    DiagnosticLog.record('api.response', fields: {
      'operation': 'HomeTimeline',
      'status': 200,
      'cookie': 'auth_token=private-cookie-value; ct0=private-csrf-value',
      'authorization': 'Bearer private-bearer-value',
      'url': 'https://api.x.com/private?query=private-query-value',
    });
    DiagnosticLog.recordError(
      'flutter.error',
      Exception('private exception text'),
      StackTrace.fromString(
          '#0 Widget.build (https://example.com/private?token=private-stack-value)'),
    );

    final output = await DiagnosticLog.exportText();
    expect(output, contains('operation=HomeTimeline'));
    expect(output, contains('status=200'));
    expect(output, contains('Exception'));
    expect(output, contains('[URL]'));
    expect(output, isNot(contains('private-cookie-value')));
    expect(output, isNot(contains('private-csrf-value')));
    expect(output, isNot(contains('private-bearer-value')));
    expect(output, isNot(contains('private-query-value')));
    expect(output, isNot(contains('private-stack-value')));
    expect(output, isNot(contains('private exception text')));
  });

  test('diagnostic export retains only a bounded recent event window',
      () async {
    for (var index = 0; index < 350; index++) {
      DiagnosticLog.record('bounded.event', fields: {'index': index});
    }

    final output = await DiagnosticLog.exportText();
    expect(output, isNot(contains('index=0')));
    expect(output, contains('index=349'));
    expect('bounded.event'.allMatches(output).length, lessThanOrEqualTo(300));
  });
}
