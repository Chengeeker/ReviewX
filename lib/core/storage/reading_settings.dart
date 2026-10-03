import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'storage_service.dart';

const readingDefaults = <String, dynamic>{
  'relativeTime': true,
  'showYear': false,
  'showWeekday': false,
  'showSeconds': false,
  'utcTime': false,
  'showSource': false,
  'grokAutoTranslate': false,
  'showBanner': true,
  'cardBackground': true,
  'fontSize': 16.0,
  'lineHeight': 1.5,
  'largeImages': true,
  'imageRadius': 16.0,
  'coloredLinks': true,
  'saveHistory': true,
  'storageFolder': 'default',
  'showSensitive': false,
};

Map<String, dynamic> validatedReading(dynamic value) {
  final result = Map<String, dynamic>.from(readingDefaults);
  if (value is! Map) return result;
  for (final key in result.keys.toList()) {
    final incoming = value[key], original = result[key];
    if (original is bool && incoming is bool) result[key] = incoming;
    if (original is double && incoming is num && incoming.isFinite) {
      result[key] = incoming.toDouble();
    }
    if (key == 'storageFolder' &&
        const ['default', 'me', 'author'].contains(incoming)) {
      result[key] = incoming;
    }
  }
  result['fontSize'] = (result['fontSize'] as double).clamp(12.0, 24.0);
  result['lineHeight'] = (result['lineHeight'] as double).clamp(1.1, 2.0);
  result['imageRadius'] = (result['imageRadius'] as double).clamp(0.0, 28.0);
  return result;
}

class ReadingNotifier extends StateNotifier<Map<String, dynamic>> {
  ReadingNotifier(this.storage) : super(Map.from(readingDefaults)) {
    reload();
  }
  final StorageService storage;
  void reload() {
    try {
      state = validatedReading(jsonDecode(
          storage.preferences.getString('reading_settings') ?? '{}'));
    } catch (_) {
      state = Map.from(readingDefaults);
    }
  }

  Future<void> set(String key, dynamic value) async {
    final updated = validatedReading({...state, key: value});
    if (!await storage.preferences
        .setString('reading_settings', jsonEncode(updated))) {
      throw StateError('保存设置失败');
    }
    state = updated;
  }
}

final readingProvider =
    StateNotifierProvider<ReadingNotifier, Map<String, dynamic>>(
        (ref) => ReadingNotifier(ref.watch(storageServiceProvider)));

/// Local browsing history stores minimal navigation metadata, never credentials.
class BrowsingHistory {
  BrowsingHistory(this.storage);
  final StorageService storage;
  List<Map<String, dynamic>> read(String accountId) {
    try {
      final data = jsonDecode(
          storage.preferences.getString('history_$accountId') ?? '[]');
      return data is List
          ? data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .take(200)
              .toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> add(String accountId,
      {required String id,
      required String url,
      required String title,
      required String author}) async {
    final list = read(accountId)..removeWhere((e) => e['id'] == id);
    list.insert(0, {
      'id': id,
      'url': url,
      'title': title.length > 140 ? title.substring(0, 140) : title,
      'author': author,
      'time': DateTime.now().toIso8601String()
    });
    await storage.preferences
        .setString('history_$accountId', jsonEncode(list.take(200).toList()));
  }

  Future<void> clear(String accountId) =>
      storage.preferences.remove('history_$accountId');
}
