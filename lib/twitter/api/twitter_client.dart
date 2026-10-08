import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../auth/session.dart';
import '../models/social_models.dart';
import 'transaction_id.dart';
import 'x_request_headers.dart';

class TwitterFailure implements Exception {
  const TwitterFailure(this.message,
      {this.sessionExpired = false, this.uncertain = false});
  final String message;
  final bool sessionExpired, uncertain;
  @override
  String toString() => message;
}

class TwitterClient {
  TwitterClient({Dio? dio, TransactionIds? transactions})
      : _dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
                followRedirects: false,
                validateStatus: (_) => true)),
        _transactions = transactions ?? TransactionIds();
  final Dio _dio;
  final TransactionIds _transactions;
  TwitterSession? session;
  Map<String, dynamic>? _protocol;
  final Set<CancelToken> _active = {};
  static const userAgent = XRequestHeaders.userAgent;
  // Public X web client identifier, not an account credential.
  static const _bearer =
      'AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA';
  void cancelAll() {
    for (final token in _active.toList()) {
      token.cancel();
    }
  }

  Future<Map<String, dynamic>> call(
      String operation, Map<String, dynamic> variables) async {
    final captured = session;
    if (captured == null) throw const TwitterFailure('请登录 X');
    final protocol = _protocol ??= object(jsonDecode(
        await rootBundle.loadString('assets/twitter_protocol.json')));
    final config = object(protocol[operation]);
    if (config.isEmpty) throw const TwitterFailure('接口配置缺失');
    final id = config['id'] as String, method = config['method'] as String;
    final path = '/graphql/$id/$operation';
    if (!identical(session, captured)) {
      throw const TwitterFailure('账号已切换，请重新加载');
    }
    return _request(path, method, variables, config: config, queryId: id);
  }

  /// Fixed first-party endpoints only; callers cannot redirect account cookies.
  Future<Map<String, dynamic>> rest(String path, Map<String, dynamic> fields) {
    if (!const {
      '/1.1/friendships/create.json',
      '/1.1/friendships/destroy.json',
      '/2/notifications/all/last_seen_cursor.json',
    }.contains(path)) {
      throw const TwitterFailure('不支持的 X 接口');
    }
    return _request(path, 'POST', fields);
  }

  Future<Map<String, dynamic>> accountSettings() =>
      _request('/1.1/account/settings.json', 'GET', {
        'include_mention_filter': true,
        'include_nsfw_user_flag': true,
        'include_nsfw_admin_flag': true,
        'include_ranked_timeline': true,
        'include_alt_text_compose': true,
        'ext': 'ssoConnections',
        'include_country_code': true,
      });

  Future<Map<String, dynamic>> trendsGuide(
          {int count = 20, bool personalized = false}) =>
      _request('/2/guide.json', 'GET', {
        'include_profile_interstitial_type': 1,
        'include_blocking': 1,
        'include_blocked_by': 1,
        'include_followed_by': 1,
        'include_want_retweets': 1,
        'include_mute_edge': 1,
        'include_can_dm': 1,
        'include_can_media_tag': 1,
        'include_ext_has_nft_avatar': 1,
        'include_ext_is_blue_verified': 1,
        'include_ext_verified_type': 1,
        'include_ext_profile_image_shape': 1,
        'skip_status': 1,
        'cards_platform': 'Web-12',
        'include_cards': 1,
        'include_ext_alt_text': true,
        'include_ext_limited_action_results': true,
        'include_quote_count': true,
        'include_reply_count': 1,
        'tweet_mode': 'extended',
        'include_ext_views': true,
        'include_entities': true,
        'include_user_entities': true,
        'include_ext_media_color': true,
        'include_ext_media_availability': true,
        'include_ext_sensitive_media_warning': true,
        'include_ext_trusted_friends_metadata': true,
        'send_error_codes': true,
        'simple_quoted_tweet': true,
        if (!personalized) 'tab_category': 'objective_trends',
        'count': count,
        'ext':
            'mediaStats,highlightedLabel,hasNftAvatar,voiceInfo,birdwatchPivot,superFollowMetadata,unmentionInfo,editControl',
      });

  Future<List<dynamic>> recommendedUsers(String userId) async {
    final data = await _requestRaw('/1.1/users/recommendations.json', 'GET', {
      'user_id': userId,
      'display_location': 'profile_accounts_sidebar',
      'limit': 10,
      'pc': true,
      'skip_status': 1,
      'include_profile_interstitial_type': 1,
      'include_blocking': 1,
      'include_blocked_by': 1,
      'include_followed_by': 1,
      'include_ext_is_blue_verified': 1,
    });
    if (data is! List) throw const TwitterFailure('X 推荐用户结构已变化，请更新客户端');
    return data;
  }

  Future<Map<String, dynamic>> _request(
      String path, String method, Map<String, dynamic> variables,
      {Map<String, dynamic>? config, String? queryId}) async {
    final data = await _requestRaw(path, method, variables,
        config: config, queryId: queryId);
    if (data is! Map) {
      throw TwitterFailure('X 返回了无法识别的数据', uncertain: method == 'POST');
    }
    return object(data);
  }

  Future<dynamic> _requestRaw(
      String path, String method, Map<String, dynamic> variables,
      {Map<String, dynamic>? config, String? queryId}) async {
    final captured = session;
    if (captured == null) throw const TwitterFailure('请登录 X');
    final graphql = config != null;
    final token = CancelToken();
    _active.add(token);
    var dispatched = false;
    try {
      final transaction = await _transactions.create(method, path);
      if (!identical(session, captured) || token.isCancelled) {
        throw const TwitterFailure('请求已取消');
      }
      final payload = {
        'variables': variables,
        'features': config?['features'] ?? {},
        'fieldToggles': config?['fieldToggles'] ?? {},
        'queryId': queryId
      };
      dispatched = true;
      final response = await _dio.request<dynamic>('https://api.x.com$path',
          data: method == 'POST' ? (graphql ? payload : variables) : null,
          queryParameters: method == 'GET'
              ? graphql
                  ? {
                      'variables': jsonEncode(variables),
                      'features': jsonEncode(payload['features']),
                      'fieldToggles': jsonEncode(payload['fieldToggles'])
                    }
                  : variables
              : null,
          cancelToken: token,
          options: Options(method: method, headers: {
            'Authorization': 'Bearer $_bearer',
            'Cookie': captured.cookie,
            'x-csrf-token': captured.csrf,
            'x-twitter-active-user': 'yes',
            'x-twitter-auth-type': 'OAuth2Session',
            'x-twitter-client-language': 'zh-cn',
            'x-client-transaction-id': transaction,
            'User-Agent': userAgent,
            'Origin': 'https://x.com',
            'Referer': path.endsWith('/SearchTimeline')
                ? 'https://x.com/search?q=${Uri.encodeQueryComponent('${variables['rawQuery'] ?? ''}')}'
                : 'https://x.com/',
            'Content-Type': graphql
                ? 'application/json'
                : Headers.formUrlEncodedContentType,
          }));
      if (!identical(session, captured)) {
        throw const TwitterFailure('账号已切换，请重新加载');
      }
      final body = object(response.data);
      final errors = array(body['errors']).map(object).toList();
      final expired = response.statusCode == 401 ||
          errors.any((e) => [32, 89, 215].contains(count(e['code'])));
      if (expired) {
        throw const TwitterFailure('X 会话已过期，请重新登录', sessionExpired: true);
      }
      if (response.statusCode == 429 ||
          errors.any((e) => count(e['code']) == 88)) {
        throw const TwitterFailure('X 请求频率受限，请稍后手动重试');
      }
      if (response.statusCode == 403) {
        throw const TwitterFailure('X 拒绝请求，请检查账号或稍后重试');
      }
      if (response.statusCode != 200 || errors.isNotEmpty) {
        throw TwitterFailure('X 请求失败（${response.statusCode}），请稍后重试',
            uncertain: method == 'POST' && (response.statusCode ?? 500) >= 500);
      }
      if (!graphql) return response.data;
      if (body['data'] is! Map) {
        throw TwitterFailure('X 返回了无法识别的数据', uncertain: method == 'POST');
      }
      return object(body['data']);
    } on TwitterFailure {
      rethrow;
    } on DioException catch (error) {
      final message = switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          '连接 X 超时，请检查 VPN 或代理是否开启及可用，然后重试',
        DioExceptionType.connectionError => '无法连接 X，请检查网络、VPN 或代理，然后重试',
        DioExceptionType.badCertificate => 'X 安全连接验证失败，请检查设备时间及网络配置',
        DioExceptionType.cancel => '请求已取消',
        _ => 'X 网络请求失败，请检查网络、VPN 或代理，然后重试',
      };
      throw TwitterFailure(
          dispatched && method == 'POST' ? '结果尚未确认，请刷新帖子核对后再操作' : message,
          uncertain: dispatched && method == 'POST');
    } catch (_) {
      throw TwitterFailure('连接 X 的接口准备失败，请稍后重试',
          uncertain: dispatched && method == 'POST');
    } finally {
      _active.remove(token);
    }
  }

  Future<String?> initialUserId(String cookie) async {
    final fromCookie = TwitterSession.userIdFromCookie(cookie);
    if (fromCookie != null) return fromCookie;
    try {
      final response = await _dio.get<String>('https://x.com/home',
          options: Options(
              headers: {'Cookie': cookie, 'User-Agent': userAgent},
              responseType: ResponseType.plain));
      final html = response.data ?? '';
      return RegExp(r'"user_id"\s*:\s*"(\d+)"').firstMatch(html)?.group(1) ??
          RegExp(r'"userId"\s*:\s*"(\d+)"').firstMatch(html)?.group(1) ??
          RegExp(r'"rest_id"\s*:\s*"(\d+)"').firstMatch(html)?.group(1);
    } catch (_) {
      throw const TwitterFailure('无法确认登录身份，请检查网络后重试');
    }
  }
}
