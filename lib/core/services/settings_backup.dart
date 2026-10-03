import 'dart:convert';
import 'package:dio/dio.dart';
import '../storage/storage_service.dart';
import '../storage/reading_settings.dart';

const _appearanceKeys = {
  'theme_mode',
  'use_dynamic_color',
  'key_theme_color_index',
  'key_is_pure_black_dark',
  'haptics',
  'floating_nav',
  'custom_font_weight',
  'font_weight_delta',
};

/// Whitelisted settings only. X sessions, WebDAV secrets and history stay local.
class SettingsBackup {
  SettingsBackup(this.storage);
  final StorageService storage;
  Map<String, dynamic> export() => {
        'app': 'com.review.x',
        'schema': 1,
        'appearance': {
          for (final key in _appearanceKeys)
            if (storage.preferences.get(key) != null)
              key: storage.preferences.get(key)
        },
        'reading': validatedReading(jsonDecode(
            storage.preferences.getString('reading_settings') ?? '{}')),
      };
  Future<void> restore(dynamic value) async {
    if (value is! Map ||
        value['app'] != 'com.review.x' ||
        value['schema'] != 1 ||
        value['reading'] is! Map ||
        value['appearance'] is! Map) {
      throw const FormatException('这不是 ReviewX 的有效设置备份');
    }
    final appearance = value['appearance'] as Map;
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
    await storage.preferences.setString(
        'reading_settings', jsonEncode(validatedReading(value['reading'])));
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

  Future<void> upload(String endpoint, String user, String password) async {
    final dio = _connection(endpoint, user, password);
    try {
      await dio.put('Review_X_settings.json',
          data: jsonEncode(export()),
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
        if (received > 256 * 1024 || total > 256 * 1024) {
          tooLarge = true;
          cancel.cancel('备份文件过大');
        }
      });
      final bytes = response.data as List<int>;
      if (bytes.length > 256 * 1024) throw const FormatException('备份文件过大');
      await restore(jsonDecode(utf8.decode(bytes)));
    } on DioException {
      if (tooLarge) throw const FormatException('备份文件过大');
      throw StateError('无法读取 WebDAV 备份，请检查地址和账号');
    } finally {
      dio.close();
    }
  }
}
