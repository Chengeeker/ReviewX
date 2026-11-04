import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review_x/core/theme/app_theme.dart';
import 'package:review_x/core/utils/haptic_feedback_util.dart';

void main() {
  for (final mode in ['light', 'dark', 'black']) {
    testWidgets(
      '$mode taps and long presses have no ink but retain actions and haptics',
      (tester) async {
        final theme = mode == 'light'
            ? AppTheme.lightTheme()
            : AppTheme.darkTheme(isPureBlack: mode == 'black');
        final haptics = <Object?>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
        final oldEnabled = HapticFeedbackUtil.isEnabled;
        HapticFeedbackUtil.isEnabled = true;
        addTearDown(() {
          HapticFeedbackUtil.isEnabled = oldEnabled;
          HapticFeedbackUtil.resetForTesting();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });
        var taps = 0;
        var holds = 0;
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: RepaintBoundary(
                key: boundaryKey,
                child: Column(
                  children: [
                    Material(
                      child: InkWell(
                        key: const ValueKey('ink'),
                        onTap: () => taps++,
                        onLongPress: () => holds++,
                        child: const SizedBox(
                          width: 220,
                          height: 60,
                          child: Text('InkWell'),
                        ),
                      ),
                    ),
                    ListTile(
                      key: const ValueKey('tile'),
                      title: const Text('ListTile'),
                      onTap: () => taps++,
                    ),
                    TextButton(
                      key: const ValueKey('text'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red)
                          .copyWith(overlayColor: noPressedOverlay),
                      onPressed: () => taps++,
                      child: const Text('Text'),
                    ),
                    FilledButton(
                      key: const ValueKey('filled'),
                      onPressed: () => taps++,
                      child: const Text('Filled'),
                    ),
                    IconButton(
                      key: const ValueKey('icon'),
                      onPressed: () => taps++,
                      icon: const Icon(Icons.settings),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<Uint8List> pixels() async => (await tester.runAsync(() async {
              final boundary = boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!
                  .buffer
                  .asUint8List();
              image.dispose();
              return bytes;
            }))!;

        for (final key in ['ink', 'tile', 'text', 'filled', 'icon']) {
          final before = await pixels();
          HapticFeedbackUtil.resetForTesting();
          haptics.clear();
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(ValueKey(key))),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            listEquals(before, await pixels()),
            isTrue,
            reason: '$key must not draw a pressed overlay or ripple',
          );
          expect(haptics, ['HapticFeedbackType.lightImpact']);
          await gesture.up();
          await tester.pumpAndSettle();
        }
        expect(taps, 5);
        final before = await pixels();
        final hold = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('ink'))),
        );
        await tester.pump(const Duration(milliseconds: 700));
        expect(holds, 1);
        expect(listEquals(before, await pixels()), isTrue);
        await hold.up();
        await tester.pumpAndSettle();

        // Component-specific M3 defaults must not restore a pressed state layer.
        final overlays = [
          theme.radioTheme.overlayColor,
          theme.checkboxTheme.overlayColor,
          theme.switchTheme.overlayColor,
          theme.tabBarTheme.overlayColor,
          theme.navigationBarTheme.overlayColor,
          theme.searchBarTheme.overlayColor,
          theme.outlinedButtonTheme.style!.overlayColor,
          theme.elevatedButtonTheme.style!.overlayColor,
        ];
        for (final overlay in overlays) {
          expect(overlay!.resolve({WidgetState.pressed}), Colors.transparent);
          expect(overlay.resolve({WidgetState.focused}), isNull);
          expect(overlay.resolve({WidgetState.hovered}), isNull);
        }
        expect(theme.focusColor.a, greaterThan(0));
        expect(
          WidgetStateProperty.resolveAs(theme.sliderTheme.overlayColor, {
            WidgetState.dragged,
          }),
          Colors.transparent,
        );
        expect(
          WidgetStateProperty.resolveAs(theme.sliderTheme.overlayColor, {
            WidgetState.focused,
          })!
              .a,
          greaterThan(0),
        );

        HapticFeedbackUtil.isEnabled = false;
        haptics.clear();
        await tester.tap(find.byKey(const ValueKey('text')));
        await tester.pumpAndSettle();
        expect(taps, 6);
        expect(haptics, isEmpty);
      },
    );
  }
}
