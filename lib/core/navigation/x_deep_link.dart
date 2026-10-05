import 'package:flutter/services.dart';

enum XLinkKind {
  post,
  profile,
  home,
  explore,
  search,
  notifications,
  bookmarks,
  other,
}

class XLinkTarget {
  const XLinkTarget._(this.kind, this.uri,
      {this.postId, this.handle, this.query});

  static const supportedHosts = <String>{
    'x.com',
    'www.x.com',
    'twitter.com',
    'www.twitter.com',
    'mobile.twitter.com',
  };

  final XLinkKind kind;
  final Uri uri;
  final String? postId;
  final String? handle;
  final String? query;

  static bool supportsHost(String host) => supportedHosts.contains(host);

  static XLinkTarget? parse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        !supportsHost(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.port != (uri.scheme.toLowerCase() == 'https' ? 443 : 80)) {
      return null;
    }

    final segments = uri.pathSegments;
    for (var i = 0; i + 1 < segments.length; i++) {
      final segment = segments[i].toLowerCase();
      final id = segments[i + 1];
      if ((segment == 'status' || segment == 'statuses') &&
          RegExp(r'^\d{1,30}$').hasMatch(id)) {
        return XLinkTarget._(XLinkKind.post, uri, postId: id);
      }
    }

    final path = segments.map((segment) => segment.toLowerCase()).toList();
    if (path.isEmpty) return XLinkTarget._(XLinkKind.home, uri);
    if (path.first == 'explore') {
      return XLinkTarget._(XLinkKind.explore, uri);
    }
    if (path.first == 'home') return XLinkTarget._(XLinkKind.home, uri);
    if (path.first == 'notifications' ||
        (path.length > 1 && path[0] == 'i' && path[1] == 'notifications')) {
      return XLinkTarget._(XLinkKind.notifications, uri);
    }
    if (path.length > 1 && path[0] == 'i' && path[1] == 'bookmarks') {
      return XLinkTarget._(XLinkKind.bookmarks, uri);
    }
    if (path.first == 'search') {
      return XLinkTarget._(XLinkKind.search, uri,
          query: uri.queryParameters['q']);
    }

    final handle = segments.length == 1 ? segments.single : '';
    if (RegExp(r'^[A-Za-z0-9_]{1,15}$').hasMatch(handle)) {
      return XLinkTarget._(XLinkKind.profile, uri, handle: handle);
    }
    return XLinkTarget._(XLinkKind.other, uri);
  }
}

class XDeepLinkChannel {
  static const _channel = MethodChannel('com.review.x/deep_links');

  static Future<String?> consumeInitialLink() =>
      _channel.invokeMethod<String>('consumeInitialLink');

  static void setHandler(Future<bool> Function(String link) onLink) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openLink' || call.arguments is! String) return false;
      return onLink(call.arguments as String);
    });
  }

  static void clearHandler() => _channel.setMethodCallHandler(null);
}
