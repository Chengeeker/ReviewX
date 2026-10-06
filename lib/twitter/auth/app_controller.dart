import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/twitter_client.dart';
import '../models/social_models.dart';
import '../repositories/twitter_adapter.dart';
import 'session.dart';
import 'x_web_auth.dart';
import '../../core/services/notification_poll.dart';
import '../cache/local_x_cache.dart';

class AppController extends ChangeNotifier {
  AppController({
    TwitterClient? client,
    SessionStore? store,
    this.localCache,
  })  : client = client ?? TwitterClient(),
        store = store ?? const SessionStore() {
    adapter = TwitterAdapter(this.client);
  }
  final TwitterClient client;
  late final TwitterAdapter adapter;
  final SessionStore store;
  final LocalXCache? localCache;
  SocialUser? me;
  bool ready = false, busy = false, expired = false;
  String? startupError;
  String loginStage = '尚未开始';
  int epoch = 0;
  final Map<String, SocialPost> _updated = {};
  final Set<String> _pending = {}, _uncertain = {};
  bool get loggedIn => client.session != null;
  Future<void> restore() async {
    startupError = null;
    try {
      client.session = await store.read();
      final session = client.session;
      me = session == null ? null : localCache?.readProfile(session.userId);
    } catch (_) {
      startupError = '无法读取安全会话存储，请重试或清除登录信息';
      me = null;
    }
    ready = true;
    notifyListeners();
    final session = client.session;
    if (session != null &&
        (me == null ||
            localCache?.profileNeedsRefresh(session.userId) != false)) {
      unawaited(_refreshProfileSnapshot(session.userId, epoch));
    }
  }

  Future<void> _refreshProfileSnapshot(
      String accountId, int capturedEpoch) async {
    try {
      final user = await adapter.user(accountId);
      if (epoch != capturedEpoch || client.session?.userId != accountId) return;
      me = user.preservingCounts(me);
      await localCache?.writeProfile(accountId, me!);
      if (epoch == capturedEpoch) notifyListeners();
    } catch (error) {
      if (epoch == capturedEpoch && client.session?.userId == accountId) {
        report(error);
      }
    }
  }

  SocialPost effective(SocialPost post) => _updated[post.id] ?? post;
  bool actionBlocked(String id) =>
      _pending.contains(id) || _uncertain.contains(id) || expired;
  bool isUncertain(String id) => _uncertain.contains(id);
  void ingest(Iterable<SocialPost> posts) {
    void absorb(SocialPost post) {
      if (!_pending.contains(post.id)) {
        _updated[post.id] = post;
        _uncertain.remove(post.id);
      }
      if (post.quote != null) absorb(post.quote!);
    }

    for (final post in posts) {
      absorb(post);
    }
    while (_updated.length > 500) {
      final removable = _updated.keys
          .where((id) => !_pending.contains(id) && !_uncertain.contains(id));
      if (removable.isEmpty) break;
      _updated.remove(removable.first);
    }
    notifyListeners();
  }

  void report(Object error) {
    if (error is TwitterFailure && error.sessionExpired) {
      expired = true;
      notifyListeners();
    }
  }

  Future<void> login(String rawCookie) async {
    await _withLoginBusy((previous) async {
      await _installSession(TwitterSession.normalize(rawCookie), previous);
    });
    await _syncNotifications();
  }

  Future<bool> loginWithWeb() async {
    var accepted = false;
    await _withLoginBusy((previous) async {
      loginStage = '等待 X 登录';
      final completed = await XWebAuth.login(validate: (cookies) async {
        try {
          await _installSession(TwitterSession.fromCookies(cookies), previous);
          accepted = true;
          return true;
        } catch (_) {
          client.session = previous;
          return false;
        }
      });
      accepted = completed && accepted;
    });
    if (accepted) await _syncNotifications();
    return accepted;
  }

  Future<void> _withLoginBusy(
      Future<void> Function(TwitterSession? previous) action) async {
    if (busy) throw const TwitterFailure('账号操作正在进行，请等待后重试');
    busy = true;
    notifyListeners();
    final previous = client.session;
    try {
      await action(previous);
    } catch (_) {
      client.session = previous;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _installSession(String cookie, TwitterSession? previous) async {
    try {
      loginStage = '确认用户 ID';
      final id = await client.initialUserId(cookie);
      if (id == null) throw const TwitterFailure('无法确认 X 登录身份，请重新登录');
      client.cancelAll();
      final candidate = TwitterSession(cookie, id);
      client.session = candidate;
      final user =
          await adapter.validateSession(onStage: (stage) => loginStage = stage);
      loginStage = '保存安全会话';
      await store.save(candidate);
      me = user.preservingCounts(me);
      try {
        await localCache?.writeProfile(candidate.userId, me!);
      } catch (_) {
        // Profile snapshots are optional; they must not invalidate a saved login.
      }
      expired = false;
      startupError = null;
      _updated.clear();
      _pending.clear();
      _uncertain.clear();
      epoch++;
      loginStage = '账号验证完成';
    } catch (_) {
      client.session = previous;
      rethrow;
    }
  }

  Future<void> _syncNotifications() async {
    try {
      await NotificationPoll.sync();
    } catch (_) {/* Account login remains valid if scheduling fails. */}
  }

  Future<void> logout() async {
    if (busy) return;
    final previousAccount = client.session?.userId;
    await store.clear();
    client.cancelAll();
    client.session = null;
    me = null;
    expired = false;
    startupError = null;
    _updated.clear();
    _pending.clear();
    _uncertain.clear();
    epoch++;
    notifyListeners();
    if (previousAccount != null) {
      try {
        await localCache?.clearAccount(previousAccount);
      } catch (_) {
        // A local-cache failure must not undo a completed logout.
      }
    }
    await NotificationPoll.sync();
  }

  Future<void> validateSession() async {
    if (busy) return;
    final session = client.session, capturedEpoch = epoch;
    if (session == null) throw const TwitterFailure('请登录 X');
    busy = true;
    notifyListeners();
    try {
      final user = await adapter.validateSession();
      if (epoch != capturedEpoch) throw const TwitterFailure('账号已切换');
      me = user.preservingCounts(me);
      await localCache?.writeProfile(session.userId, me!);
      expired = false;
    } catch (error) {
      report(error);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> act(SocialPost rawPost, {required bool like}) async {
    final post = effective(rawPost);
    if (actionBlocked(post.id)) return;
    final capturedEpoch = epoch;
    _pending.add(post.id);
    _updated[post.id] = like
        ? post.withActions(liked: !post.liked)
        : post.withActions(reposted: !post.reposted);
    notifyListeners();
    try {
      if (like) {
        await adapter.like(post.id, !post.liked);
      } else {
        await adapter.repost(post.id, !post.reposted);
      }
    } catch (error) {
      if (capturedEpoch == epoch) {
        _updated[post.id] = post;
        if (error is TwitterFailure && error.uncertain) _uncertain.add(post.id);
        report(error);
      }
      rethrow;
    } finally {
      if (capturedEpoch == epoch) {
        _pending.remove(post.id);
        notifyListeners();
      }
    }
  }

  Future<void> bookmark(SocialPost rawPost) async {
    final post = effective(rawPost);
    if (actionBlocked(post.id)) return;
    final capturedEpoch = epoch;
    _pending.add(post.id);
    notifyListeners();
    try {
      await adapter.bookmark(post.id, !post.bookmarked);
      if (capturedEpoch == epoch) {
        _updated[post.id] =
            effective(post).withActions(bookmarked: !post.bookmarked);
      }
    } catch (error) {
      if (capturedEpoch == epoch) {
        if (error is TwitterFailure && error.uncertain) _uncertain.add(post.id);
        report(error);
      }
      rethrow;
    } finally {
      if (capturedEpoch == epoch) {
        _pending.remove(post.id);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    client.cancelAll();
    super.dispose();
  }
}

final appControllerProvider = ChangeNotifierProvider<AppController>(
  (ref) => AppController(localCache: ref.watch(localXCacheProvider)),
);
