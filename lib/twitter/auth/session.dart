import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TwitterSession {
  const TwitterSession(this.cookie, this.userId);
  final String cookie, userId;
  String get csrf => cookies(cookie)['ct0']!;
  static Map<String, String> cookies(String value) {
    final result = <String, String>{};
    for (final part in value.split(';')) {
      final at = part.indexOf('=');
      if (at > 0) {
        result[part.substring(0, at).trim()] = part.substring(at + 1).trim();
      }
    }
    return result;
  }

  static String normalize(String value) {
    if (value.contains('\n') || value.contains('\r')) {
      throw const FormatException('Cookie 格式不正确');
    }
    final parsed = cookies(value);
    for (final key in ['auth_token', 'ct0']) {
      if (parsed[key]?.isNotEmpty != true) {
        throw const FormatException('请先在 X 网页完成登录');
      }
    }
    // Keep only required X session fields; other host cookies cannot enter the API.
    return ['auth_token', 'ct0', 'twid', 'gt']
        .where((key) => parsed[key]?.isNotEmpty == true)
        .map((key) => '$key=${parsed[key]}')
        .join('; ');
  }

  static String fromCookies(Map<String, String> values) {
    const allowed = ['auth_token', 'ct0', 'twid', 'gt'];
    final cookies = <String, String>{};
    for (final key in allowed) {
      final value = values[key]?.trim();
      if (value == null || value.isEmpty) continue;
      if (value.contains(';') || value.contains('\r') || value.contains('\n')) {
        throw const FormatException('X 会话 Cookie 格式不正确');
      }
      cookies[key] = value;
    }
    if (cookies['auth_token'] == null || cookies['ct0'] == null) {
      throw const FormatException('X 登录尚未完成');
    }
    return normalize(cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; '));
  }

  static String? userIdFromCookie(String value) {
    final raw = cookies(value)['twid'];
    if (raw == null) return null;
    try {
      return RegExp(r'^u=(\d+)$')
          .firstMatch(Uri.decodeComponent(raw).replaceAll('"', ''))
          ?.group(1);
    } catch (_) {
      return null;
    }
  }
}

class SessionStore {
  const SessionStore();
  static const _key = 'twitter_session_v1';
  static const _storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  Future<TwitterSession?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    final json = jsonDecode(value) as Map<String, dynamic>;
    return TwitterSession(TwitterSession.normalize(json['cookie'] as String),
        json['userId'] as String);
  }

  Future<void> save(TwitterSession session) => _storage.write(
      key: _key,
      value: jsonEncode({'cookie': session.cookie, 'userId': session.userId}));
  Future<void> clear() => _storage.delete(key: _key);
}
