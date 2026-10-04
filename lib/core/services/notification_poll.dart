import 'dart:convert';
import 'package:flutter/services.dart';
import '../storage/storage_service.dart';
import 'network_routing.dart';
import '../../twitter/auth/session.dart';
import '../../twitter/api/twitter_client.dart';
import '../../twitter/repositories/twitter_adapter.dart';
import '../../twitter/models/content_models.dart';

class NotificationPoll {
  static const channel = MethodChannel('com.review.x/notifications');
  static Future<void> sync() async {
    try {
      await channel.invokeMethod(
          'sync', {'loggedIn': await const SessionStore().read() != null});
    } on MissingPluginException {/* Non Android tests. */}
  }

  static Future<List<Map<String, dynamic>>> run() async {
    final storage = await StorageService.init();
    if (!storage.getBool('notification_enabled')) return [];
    await NetworkRouting.initialize(storage);
    final session = await const SessionStore().read();
    if (session == null) return [];
    final client = TwitterClient()..session = session;
    final page = await TwitterAdapter(client).notifications();
    // Logout/disable can happen while fetching; never notify for the old session.
    await storage.preferences.reload();
    final current = await const SessionStore().read();
    if (!storage.getBool('notification_enabled') ||
        current?.userId != session.userId ||
        current?.cookie != session.cookie) {
      return [];
    }
    final key = 'notification_seen_${session.userId}',
        previousValue = storage.preferences.getString(key);
    final previous = previousValue == null
        ? <String>{}
        : (jsonDecode(previousValue) as List).whereType<String>().toSet();
    final newItems = previousValue == null
        ? <SocialNotification>[]
        : page.notifications.where((n) => !previous.contains(n.id)).toList();
    final seen = <String>{...page.notifications.map((n) => n.id), ...previous}
        .take(500)
        .toList();
    await storage.preferences.setString(key, jsonEncode(seen));
    return [
      for (final n in newItems)
        if (storage.getBool('notification_${category(n)}', defaultValue: true))
          {
            'id': n.id,
            'message': n.message.isEmpty
                ? n.posts.firstOrNull?.text ?? 'X 有新通知'
                : n.message
          }
    ];
  }

  static String category(SocialNotification n) => n.icon.contains('heart')
      ? 'likes'
      : n.icon.contains('retweet')
          ? 'reposts'
          : n.icon.contains('person')
              ? 'followers'
              : n.posts.isNotEmpty
                  ? 'mentions'
                  : 'other';
}
