import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_service.dart';
import '../models/social_models.dart';

/// Small, account-scoped snapshots used to paint the last home page while X
/// refreshes. Cookies, cursors, and full article bodies are never persisted.
class LocalXCache {
  LocalXCache(this.storage);

  final StorageService storage;

  static const _prefix = 'reviewx_xcache_v1_';
  static const _maxTimelinePosts = 20;
  static const _maxTimelineBytes = 512 * 1024;
  static const _timelineMaxAge = Duration(days: 14);
  static const _profileMaxAge = Duration(days: 30);
  static const _profileRefreshInterval = Duration(hours: 6);
  static const _timelineKeys = {'for_you', 'following'};

  String? _accountPrefix(String userId) =>
      RegExp(r'^\d+$').hasMatch(userId) ? '$_prefix${userId}_' : null;

  SocialUser? readProfile(String userId) {
    final prefix = _accountPrefix(userId);
    if (prefix == null) return null;
    try {
      final value = storage.preferences.getString('${prefix}profile');
      if (value == null) return null;
      final envelope = object(jsonDecode(value));
      if (!_fresh(envelope['savedAt'], _profileMaxAge)) return null;
      return SocialUser.fromCacheJson(envelope['user']);
    } catch (_) {
      return null;
    }
  }

  bool profileNeedsRefresh(String userId) {
    final prefix = _accountPrefix(userId);
    if (prefix == null) return true;
    try {
      final value = storage.preferences.getString('${prefix}profile');
      if (value == null) return true;
      final savedAt = DateTime.tryParse(
        '${object(jsonDecode(value))['savedAt'] ?? ''}',
      )?.toUtc();
      if (savedAt == null) return true;
      final age = DateTime.now().toUtc().difference(savedAt);
      return age.isNegative || age >= _profileRefreshInterval;
    } catch (_) {
      return true;
    }
  }

  Future<void> writeProfile(String userId, SocialUser user) async {
    final prefix = _accountPrefix(userId);
    if (prefix == null || user.id != userId) return;
    try {
      await storage.preferences.setString(
        '${prefix}profile',
        jsonEncode({
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'user': user.toCacheJson(),
        }),
      );
    } catch (_) {
      // Local snapshots are an optimization and never block account actions.
    }
  }

  List<SocialPost> readTimeline(String userId, String timeline) {
    final prefix = _accountPrefix(userId);
    if (prefix == null || !_timelineKeys.contains(timeline)) return const [];
    try {
      final value =
          storage.preferences.getString('${prefix}timeline_$timeline');
      if (value == null) return const [];
      final envelope = object(jsonDecode(value));
      if (envelope['schema'] != 1 ||
          !_fresh(envelope['savedAt'], _timelineMaxAge)) {
        return const [];
      }
      return array(envelope['posts'])
          .take(_maxTimelinePosts)
          .map(SocialPost.fromCacheJson)
          .whereType<SocialPost>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeTimeline(
      String userId, String timeline, List<SocialPost> posts) async {
    final prefix = _accountPrefix(userId);
    if (prefix == null || !_timelineKeys.contains(timeline) || posts.isEmpty) {
      return;
    }

    try {
      final snapshot = posts
          .take(_maxTimelinePosts)
          .map((post) => post.toCacheJson())
          .toList();
      String encode() => jsonEncode({
            'schema': 1,
            'savedAt': DateTime.now().toUtc().toIso8601String(),
            'posts': snapshot,
          });

      var encoded = encode();
      while (snapshot.isNotEmpty &&
          utf8.encode(encoded).length > _maxTimelineBytes) {
        snapshot.removeLast();
        encoded = encode();
      }
      if (snapshot.isEmpty) return;
      await storage.preferences
          .setString('${prefix}timeline_$timeline', encoded);
    } catch (_) {
      // Cached feed data is optional; a storage error never blocks refresh.
    }
  }

  Future<void> clearAccount(String userId) async {
    final prefix = _accountPrefix(userId);
    if (prefix == null) return;
    final keys = storage.preferences
        .getKeys()
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in keys) {
      await storage.preferences.remove(key);
    }
  }

  bool _fresh(dynamic savedAt, Duration maxAge) {
    final saved = DateTime.tryParse('$savedAt')?.toUtc();
    if (saved == null) return false;
    final age = DateTime.now().toUtc().difference(saved);
    return !age.isNegative && age <= maxAge;
  }
}

final localXCacheProvider = Provider<LocalXCache>(
  (ref) => LocalXCache(ref.watch(storageServiceProvider)),
);
