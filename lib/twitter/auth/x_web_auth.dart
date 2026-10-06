import 'package:flutter/services.dart';

class XWebAuthException implements Exception {
  const XWebAuthException(this.message);
  final String message;
}

class XWebAuth {
  static const _channel = MethodChannel('com.review.x/x_auth');

  static Future<String> getLoginDiagnostics() async {
    try {
      return await _channel.invokeMethod<String>('getLoginDiagnostics') ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  static Future<void> recordFlutterLifecycle(String state) async {
    if (!const {'resumed', 'inactive', 'hidden', 'paused', 'detached'}
        .contains(state)) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('recordFlutterLifecycle', state);
    } on PlatformException {
      // Diagnostics must not affect the login flow.
    } on MissingPluginException {
      // Diagnostics are unavailable on unsupported platforms.
    }
  }

  static Future<bool> login({
    required Future<bool> Function(Map<String, String> cookies) validate,
  }) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'validateCandidate' || call.arguments is! Map) {
        return false;
      }
      final cookies = <String, String>{};
      for (final entry in (call.arguments as Map).entries) {
        if (entry.key is String && entry.value is String) {
          cookies[entry.key as String] = entry.value as String;
        }
      }
      try {
        return await validate(cookies);
      } catch (_) {
        return false;
      }
    });
    try {
      return await _channel.invokeMethod<bool>('startLogin') ?? false;
    } on PlatformException {
      throw const XWebAuthException('无法打开 X 验证页面，请重试或使用 Cookie 导入。');
    } on MissingPluginException {
      throw const XWebAuthException('当前设备不支持应用内 X 登录，请使用 Cookie 导入。');
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}
