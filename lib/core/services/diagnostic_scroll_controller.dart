import 'package:flutter/widgets.dart';

import 'diagnostic_log.dart';

/// Observes framework corrections without changing scroll physics or offsets.
class DiagnosticScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _DiagnosticScrollPosition(
        physics: physics,
        context: context,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
      );
}

class _DiagnosticScrollPosition extends ScrollPositionWithSingleContext {
  _DiagnosticScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
  });

  final _clock = Stopwatch()..start();
  final _lastRecord = <String, int>{};

  void _record(String event, Map<String, Object?> fields) {
    final now = _clock.elapsedMilliseconds;
    if (now - (_lastRecord[event] ?? -200) < 150) return;
    _lastRecord[event] = now;
    DiagnosticLog.record(event, fields: fields);
  }

  @override
  void correctBy(double correction) {
    if (hasPixels && correction.abs() > 0.5) {
      _record('timeline.layout_correction', {
        'pixels': pixels.toStringAsFixed(1),
        'correction': correction.toStringAsFixed(1),
      });
    }
    super.correctBy(correction);
  }

  @override
  void correctPixels(double value) {
    if (hasPixels && (value - pixels).abs() > 0.5) {
      _record('timeline.boundary_correction', {
        'from': pixels.toStringAsFixed(1),
        'to': value.toStringAsFixed(1),
        'max': hasContentDimensions ? maxScrollExtent.toStringAsFixed(1) : null,
      });
    }
    super.correctPixels(value);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (hasContentDimensions &&
        (maxScrollExtent - this.maxScrollExtent).abs() > 0.5) {
      _record('timeline.extent_changed', {
        'pixels': pixels.toStringAsFixed(1),
        'oldMax': this.maxScrollExtent.toStringAsFixed(1),
        'newMax': maxScrollExtent.toStringAsFixed(1),
        'viewport': viewportDimension.toStringAsFixed(1),
      });
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
