import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../twitter/auth/session.dart';
import 'cache_service.dart';
import 'network_routing.dart';
import '../storage/storage_service.dart';
import '../storage/reading_settings.dart';

const _appearanceKeys = {
  'theme_mode',
  'use_dynamic_color',
  'key_theme_color_index',
  'key_is_pure_black_dark',
  'haptics',
  'floating_nav',
  'use_liquid_glass_effect',
  'custom_font_weight',
  'font_weight_delta',
};

/// Legacy settings backups remain readable; credentials require explicit opt-in.
class SettingsBackup {
  SettingsBackup(this.storage,
      {this.secure = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true))});
  final StorageService storage;
  final FlutterSecureStorage secure;
  static const maxBytes = 8 * 1024 * 1024;
  static bool _localKey(String key) =>
      _appearanceKeys.contains(key) ||
      const {
        'reading_settings',
        'network_config',
        'refresh_rate',
        'notification_enabled',
        'notification_likes',
        'notification_reposts',
        'notification_followers',
        'notification_replies',
        'notification_mentions',
        'notification_other',
        CacheService.thresholdKey
      }.contains(key) ||
      RegExp(r'^(history_|search_history_|notification_seen_)\d+$')
          .hasMatch(key) ||
      RegExp(r'^reviewx_xcache_v1_\d+_(profile|timeline_for_you|timeline_following)$')
          .hasMatch(key);

  Future<Map<String, dynamic>> exportAll(
      {bool includeCredentials = false}) async {
    final config =
        jsonDecode(await secure.read(key: 'webdav_config') ?? '{}') as Map;
    final result = {
      ...export(),
      'backup_mode': includeCredentials ? 'full' : 'safe',
      'local': {
        for (final key in storage.preferences.getKeys())
          if (_localKey(key)) key: storage.preferences.get(key)
      },
      'webdav': {
        for (final key in ['url', 'user', 'directory'])
          if (config[key] is String) key: config[key]
      },
    };
    if (includeCredentials) {
      final session = await secure.read(key: 'twitter_session_v1');
      result['credentials'] = {
        if (session != null) 'session': _session(jsonDecode(session)),
        if (config['password'] is String) 'webdav_password': config['password'],
      };
    }
    if (utf8.encode(jsonEncode(result)).length > maxBytes) {
      throw const FormatException('备份文件过大');
    }
    return result;
  }

  static Map<String, dynamic> _session(dynamic value) {
    if (value is! Map ||
        value['cookie'] is! String ||
        value['userId'] is! String ||
        !RegExp(r'^\d+$').hasMatch(value['userId'])) {
      throw const FormatException('备份中的 X 会话无效');
    }
    final cookie = TwitterSession.normalize(value['cookie']);
    final cookieId = TwitterSession.userIdFromCookie(cookie);
    if (cookieId != null && cookieId != value['userId']) {
      throw const FormatException('备份中的 X 账号不一致');
    }
    return {'cookie': cookie, 'userId': value['userId']};
  }

  Map<String, dynamic> export() => {
        'app': 'com.review.x',
        'schema': 1,
        'appearance': {
          for (final key in _appearanceKeys)
            if (storage.preferences.get(key) != null)
              key: storage.preferences.get(key)
        },
        'cache': {
          CacheService.thresholdKey: storage.getInt(
            CacheService.thresholdKey,
            defaultValue: CacheService.defaultThresholdMb,
          ),
        },
        'reading': validatedReading(jsonDecode(
            storage.preferences.getString('reading_settings') ?? '{}')),
      };
  Future<void> restore(dynamic value, {bool allowCredentials = false}) async {
    if (value is! Map ||
        value['app'] != 'com.review.x' ||
        value['schema'] != 1 ||
        value['reading'] is! Map ||
        value['appearance'] is! Map) {
      throw const FormatException('这不是 ReviewX 的有效设置备份');
    }
    final credentials = value['credentials'];
    final full = value['backup_mode'] == 'full';
    if (full && !allowCredentials) {
      throw const FormatException('恢复全量备份需要确认替换登录凭据');
    }
    final session = full && credentials is Map && credentials['session'] != null
        ? _session(credentials['session'])
        : null;
    final webdavPassword =
        full && credentials is Map ? credentials['webdav_password'] : null;
    if (webdavPassword != null && webdavPassword is! String) {
      throw const FormatException('备份中的 WebDAV 密码无效');
    }
    final local = value['local'];
    if (local != null &&
        (local is! Map ||
            local.entries.any((e) =>
                e.key is! String ||
                !_localKey(e.key) ||
                !(e.value is String ||
                    e.value is bool ||
                    e.value is int ||
                    e.value is double ||
                    (e.value is List && e.value.every((v) => v is String)))))) {
      throw const FormatException('备份中的本地数据无效');
    }
    final appearance = value['appearance'] as Map;
    if (local is Map) {
      for (final entry in local.entries) {
        if (entry.key == 'network_config') {
          final config = jsonDecode(entry.value as String) as Map;
          NetworkConfig(
            mode: ConnectionMode.values.byName(config['mode'] as String),
            host: config['host'] as String,
            port: config['port'] as int,
          ).validate();
        } else if (entry.key == 'refresh_rate') {
          if (entry.value is! int) throw const FormatException('刷新率设置无效');
        } else if ((entry.key as String).startsWith('notification_') &&
            !(entry.key as String).startsWith('notification_seen_')) {
          if (entry.value is! bool) throw const FormatException('通知设置无效');
        } else if (!_appearanceKeys.contains(entry.key) &&
            entry.key != CacheService.thresholdKey) {
          jsonDecode(entry.value as String);
        }
      }
    }
    for (final key in _appearanceKeys) {
      final v = appearance[key];
      if (v is bool &&
          !const ['theme_mode', 'key_theme_color_index', 'font_weight_delta']
              .contains(key)) {
        await storage.setBool(key, v);
      } else if (v is int) {
        if (key == 'theme_mode' && v >= 0 && v <= 2 ||
            key == 'key_theme_color_index' && v >= 0 && v < 8 ||
            key == 'font_weight_delta' && v >= -300 && v <= 300) {
          await storage.setInt(key, v);
        }
      }
    }
    final cache = value['cache'];
    final threshold = cache is Map ? cache[CacheService.thresholdKey] : null;
    if (threshold is int && CacheService.thresholdsMb.contains(threshold)) {
      await storage.setInt(CacheService.thresholdKey, threshold);
    }
    await storage.preferences.setString(
        'reading_settings', jsonEncode(validatedReading(value['reading'])));
    if (local is Map) {
      for (final entry in local.entries) {
        final key = entry.key as String, v = entry.value;
        // Appearance and reading values keep the validation above.
        if (_appearanceKeys.contains(key) ||
            key == 'reading_settings' ||
            key == CacheService.thresholdKey) {
          continue;
        }
        if (v is String) await storage.preferences.setString(key, v);
        if (v is bool) await storage.preferences.setBool(key, v);
        if (v is int) await storage.preferences.setInt(key, v);
        if (v is double) await storage.preferences.setDouble(key, v);
        if (v is List) {
          await storage.preferences.setStringList(key, v.cast<String>());
        }
      }
    }
    final config = value['webdav'];
    if (config is Map) {
      final current =
          jsonDecode(await secure.read(key: 'webdav_config') ?? '{}') as Map;
      await secure.write(
          key: 'webdav_config',
          value: jsonEncode({
            ...current,
            for (final key in ['url', 'user', 'directory'])
              if (config[key] is String) key: config[key],
            if (webdavPassword != null) 'password': webdavPassword,
          }));
    }
    if (session != null) {
      await secure.write(key: 'twitter_session_v1', value: jsonEncode(session));
    }
  }

  Dio _connection(String endpoint, String user, String password) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('WebDAV 地址需要无查询参数的 HTTPS 地址');
    }
    return Dio(BaseOptions(
        baseUrl: endpoint.endsWith('/') ? endpoint : '$endpoint/',
        followRedirects: false,
        maxRedirects: 0,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$user:$password'))}'
        }));
  }

  Future<void> testConnection(
      String endpoint, String user, String password) async {
    final dio = _connection(endpoint, user, password);
    try {
      await dio.request('',
          options: Options(method: 'PROPFIND', headers: {'Depth': '0'}));
    } on DioException {
      throw StateError('连接失败，请检查服务器地址、账号与授权密码');
    } finally {
      dio.close();
    }
  }

  Future<void> upload(String endpoint, String user, String password,
      {bool includeCredentials = false, String directory = ''}) async {
    final dio = _connection(endpoint, user, password);
    try {
      if (directory.isNotEmpty) {
        await dio.request('',
            options: Options(
                method: 'MKCOL',
                validateStatus: (s) =>
                    s == 200 || s == 201 || s == 204 || s == 405));
      }
      await dio.put('Review_X_settings.json',
          data: jsonEncode(
              await exportAll(includeCredentials: includeCredentials)),
          options: Options(contentType: Headers.jsonContentType));
    } on DioException {
      throw StateError('备份提交未确认，请检查 WebDAV 文件后再操作');
    } finally {
      dio.close();
    }
  }

  Future<void> download(String endpoint, String user, String password) async {
    final dio = _connection(endpoint, user, password);
    final cancel = CancelToken();
    var tooLarge = false;
    try {
      final response = await dio.get('Review_X_settings.json',
          cancelToken: cancel,
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: (received, total) {
        if (received > maxBytes || total > maxBytes) {
          tooLarge = true;
          cancel.cancel('备份文件过大');
        }
      });
      final bytes = response.data as List<int>;
      if (bytes.length > maxBytes) throw const FormatException('备份文件过大');
      await restore(jsonDecode(utf8.decode(bytes)), allowCredentials: true);
    } on DioException {
      if (tooLarge) throw const FormatException('备份文件过大');
      throw StateError('无法读取 WebDAV 备份，请检查地址和账号');
    } finally {
      dio.close();
    }
  }
}
