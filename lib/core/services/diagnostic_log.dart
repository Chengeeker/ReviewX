import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Bounded local diagnostics. Events must describe state, never user content.
abstract final class DiagnosticLog {
  static const _maxEvents = 300;
  static const _maxBytes = 256 * 1024;
  static final _events = <String>[];
  static Future<void> _writes = Future<void>.value();
  static Future<void> _ready = Future<void>.value();
  static int _persistedCount = 0;
  static File? _file;
  static String _version = 'unknown';
  static bool _installed = false;

  static void install({required String version}) {
    if (_installed) return;
    _installed = true;
    _version = version;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      recordError('flutter.error', details.exception, details.stack);
      if (previousFlutterError != null) {
        previousFlutterError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final dispatcher = PlatformDispatcher.instance;
    final previousPlatformError = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      recordError('platform.error', error, stack);
      return previousPlatformError?.call(error, stack) ?? false;
    };
    WidgetsBinding.instance.addObserver(_lifecycleObserver);

    record('app.started', fields: {
      'version': _version,
      'platform': Platform.operatingSystem,
    });
    _ready = _loadPreviousEvents();
  }

  static void record(String event,
      {Map<String, Object?> fields = const {}, bool flush = false}) {
    final name = event
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')
        .substring(0, event.length.clamp(0, 64).toInt());
    final detail = fields.entries
        .take(12)
        .map((entry) => (entry.key, _safeValue(entry.value)))
        .where((entry) => entry.$2 != null)
        .map((entry) => '${_clean(entry.$1)}=${_clean(entry.$2!)}')
        .join(' ');
    final line = '${DateTime.now().toUtc().toIso8601String()} $name'
        '${detail.isEmpty ? '' : ' $detail'}';
    _events.add(line);
    _trimEvents();
    final file = _file;
    if (file != null) _enqueue(file, line, flush: flush);
  }

  static void recordError(String event, Object error, StackTrace? stack) {
    final frames = stack
            ?.toString()
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .take(8)
            .map(_clean)
            .join(' <- ') ??
        '';
    record(event,
        fields: {
          'type': error.runtimeType,
          if (frames.isNotEmpty) 'stack': frames,
        },
        flush: true);
  }

  static Future<String> exportText() async {
    await _ready;
    await _writes;
    return [
      'ReviewX diagnostic log',
      'Version: $_version',
      'Platform: ${Platform.operatingSystem}',
      'OS: ${_clean(Platform.operatingSystemVersion)}',
      'Credentials, post text, and API payloads are excluded.',
      '',
      ..._events,
    ].join('\n');
  }

  static Future<void> _loadPreviousEvents() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file =
          File('${directory.path}${Platform.pathSeparator}diagnostics.log');
      await file.parent.create(recursive: true);
      final previous =
          await file.exists() ? await file.readAsLines() : <String>[];
      _persistedCount = previous.length;
      final current = List<String>.of(_events);
      _events
        ..clear()
        ..addAll(previous)
        ..addAll(current);
      _trimEvents();
      _file = file;
      for (final line in current) {
        _enqueue(file, line, flush: false);
      }
    } catch (_) {
      // Logging must never prevent the app from starting.
    }
  }

  static void _enqueue(File file, String line, {required bool flush}) {
    _writes = _writes.then((_) async {
      final exists = await file.exists();
      if (!exists) _persistedCount = 0;
      final lineBytes = utf8.encode(line).length + 1;
      if (exists &&
          (await file.length() + lineBytes > _maxBytes ||
              _persistedCount >= _maxEvents)) {
        final lines = await file.readAsLines();
        var totalBytes = lines.fold<int>(
            0, (size, item) => size + utf8.encode(item).length + 1);
        while (lines.isNotEmpty &&
            (lines.length >= _maxEvents ||
                totalBytes + lineBytes > _maxBytes)) {
          totalBytes -= utf8.encode(lines.removeAt(0)).length + 1;
        }
        await file.writeAsString(
          lines.isEmpty ? '' : '${lines.join('\n')}\n',
          flush: false,
        );
        _persistedCount = lines.length;
      }
      await file.writeAsString('$line\n', mode: FileMode.append, flush: flush);
      _persistedCount++;
    }).catchError((Object _) {});
  }

  static void _trimEvents() {
    while (_events.length > _maxEvents ||
        _events.fold<int>(0, (size, line) => size + line.length) > _maxBytes) {
      _events.removeAt(0);
    }
  }

  static String _clean(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\bBearer\s+[^\s,;&]+', caseSensitive: false),
            'Bearer [REDACTED]')
        .replaceAll(
            RegExp(
                r'"(auth_token|access_token|refresh_token|oauth_token|ct0|cookie|authorization|password|secret|token)"\s*:\s*"[^"]*"',
                caseSensitive: false),
            r'"$1":"[REDACTED]"')
        .replaceAll(
            RegExp(
                r'\b(auth_token|access_token|refresh_token|oauth_token|ct0|x-csrf-token|cookie|authorization|bearer|password|token|secret|api_key|client_secret)\s*[:=]\s*[^\s,;&]+',
                caseSensitive: false),
            '[REDACTED]')
        .replaceAll(
            RegExp(r'\b(auth_token|ct0|oauth_token)=([^\s,;&]+)',
                caseSensitive: false),
            r'$1=[REDACTED]')
        .replaceAll(
            RegExp(r'https?://[^\s<>]+', caseSensitive: false), '[URL]');
    return cleaned.substring(0, cleaned.length.clamp(0, 600).toInt());
  }

  static String? _safeValue(Object? value) {
    if (value is String || value is num || value is bool || value is Type) {
      return '$value';
    }
    if (value is Enum) return value.name;
    return null;
  }

  static final _lifecycleObserver = _DiagnosticLifecycleObserver();
}

class _DiagnosticLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    DiagnosticLog.record('app.lifecycle', fields: {'state': state.name});
  }
}
