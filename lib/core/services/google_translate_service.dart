import 'dart:convert';
import 'package:dio/dio.dart';

/// Lightweight Google Translate client using the public translation API.
class GoogleTranslateService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
    validateStatus: (_) => true,
  ));

  static final Map<String, String> _cache = {};

  /// Translates [text] to [targetLang] (defaults to 'zh-CN').
  /// Returns the translated string, or null on network/parsing failure.
  static Future<String?> translate(String text,
      {String targetLang = 'zh-CN'}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final cacheKey = '$targetLang:$trimmed';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final uri =
          Uri.parse('https://translate.googleapis.com/translate_a/single')
              .replace(queryParameters: {
        'client': 'gtx',
        'sl': 'auto',
        'tl': targetLang,
        'dt': 't',
        'q': trimmed,
      });

      final response = await _dio.getUri<dynamic>(uri);
      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      dynamic data = response.data;
      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is List && data.isNotEmpty && data[0] is List) {
        final buffer = StringBuffer();
        for (final item in data[0] as List) {
          if (item is List && item.isNotEmpty && item[0] is String) {
            buffer.write(item[0]);
          }
        }
        final result = buffer.toString().trim();
        if (result.isNotEmpty) {
          _cache[cacheKey] = result;
          return result;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Determines whether [text] is likely a foreign language (no Hanzi, has alphabetic characters).
  static bool needsTranslation(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 3) return false;
    final hasChinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(trimmed);
    if (hasChinese) return false;
    final hasWords =
        RegExp(r'[a-zA-Z\u3040-\u30ff\uac00-\ud7af]').hasMatch(trimmed);
    return hasWords;
  }
}
