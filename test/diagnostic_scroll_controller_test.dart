import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/core/services/diagnostic_log.dart';
import 'package:review_x/core/services/diagnostic_scroll_controller.dart';

void main() {
  testWidgets('observing a layout correction preserves its exact offset',
      (tester) async {
    final controller = DiagnosticScrollController();
    await tester.pumpWidget(MaterialApp(
        home: ListView(
      controller: controller,
      children: const [SizedBox(height: 4000)],
    )));
    controller.jumpTo(300);
    controller.position.correctBy(-25);
    expect(controller.offset, 275);
    final log = await DiagnosticLog.exportText();
    expect(log, contains('timeline.layout_correction'));
    expect(log, contains('correction=-25.0'));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
