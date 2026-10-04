import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../storage/storage_service.dart';

enum ConnectionMode { automatic, direct, manual }

class NetworkConfig {
  const NetworkConfig(
      {this.mode = ConnectionMode.automatic, this.host = '', this.port = 0});
  final ConnectionMode mode;
  final String host;
  final int port;
  static const key = 'network_config';

  void validate() {
    if (mode != ConnectionMode.manual) return;
    if (host.isEmpty ||
        host.length > 253 ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$').hasMatch(host)) {
      throw const FormatException('请输入代理主机名或 IPv4 地址，不含协议、端口或路径');
    }
    if (port < 1 || port > 65535) throw const FormatException('端口应为 1–65535');
  }

  Map<String, dynamic> toJson() =>
      {'mode': mode.name, 'host': host, 'port': port};
  static NetworkConfig read(StorageService storage) {
    final raw = storage.preferences.getString(key);
    if (raw == null) return const NetworkConfig();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return NetworkConfig(
        mode: ConnectionMode.values.firstWhere((v) => v.name == data['mode'],
            orElse: () => ConnectionMode.automatic),
        host: data['host'] as String? ?? '',
        port: data['port'] as int? ?? 0);
  }

  Future<void> save(StorageService storage) async {
    validate();
    if (!await storage.preferences.setString(key, jsonEncode(toJson()))) {
      throw StateError('网络设置保存失败');
    }
  }
}

class SystemProxy {
  const SystemProxy(
      {this.host = '', this.port = 0, this.exclusions = const []});
  final String host;
  final int port;
  final List<String> exclusions;

  String resolve(Uri uri) {
    if (host.isEmpty || port <= 0) return 'DIRECT';
    for (final pattern in exclusions) {
      final expression = pattern.split('*').map(RegExp.escape).join('.*');
      if (pattern.isNotEmpty &&
          RegExp('^$expression\$', caseSensitive: false).hasMatch(uri.host)) {
        return 'DIRECT';
      }
    }
    return 'PROXY $host:$port';
  }
}

class NetworkRouting extends HttpOverrides {
  NetworkRouting(this.config, this.system);
  final NetworkConfig config;
  final SystemProxy system;
  static const channel = MethodChannel('com.review.x/network');

  String resolve(Uri uri) => switch (config.mode) {
        ConnectionMode.direct => 'DIRECT',
        ConnectionMode.manual => 'PROXY ${config.host}:${config.port}',
        ConnectionMode.automatic => system.resolve(uri),
      };

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = resolve;

  static Future<SystemProxy> systemProxy() async {
    try {
      final data =
          await channel.invokeMapMethod<String, dynamic>('systemProxy');
      return SystemProxy(
          host: data?['host'] as String? ?? '',
          port: data?['port'] as int? ?? 0,
          exclusions: (data?['exclusions'] as List? ?? []).cast<String>());
    } on MissingPluginException {
      return const SystemProxy();
    }
  }

  static Future<void> initialize(StorageService storage,
      {bool configurePlayer = false}) async {
    final config = NetworkConfig.read(storage);
    config.validate();
    if (configurePlayer) {
      try {
        await channel.invokeMethod<void>('configure', config.toJson());
      } on MissingPluginException {/* Non-Android platforms. */}
    }
    HttpOverrides.global = NetworkRouting(config, await systemProxy());
  }

  /// Test only the draft route, without account cookies or changing live clients.
  static Future<String> test(NetworkConfig config) async {
    config.validate();
    final routing = NetworkRouting(config, await systemProxy());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    client.findProxy = routing.resolve;
    try {
      return await (() async {
        final request = await client.getUrl(Uri.parse('https://api.x.com/'));
        request.followRedirects = false;
        final response = await request.close();
        if (response.statusCode == 407) return '代理要求认证，请使用无需认证的 HTTP 代理端口';
        if (response.statusCode >= 500) {
          return '已收到响应，但 X 服务异常（${response.statusCode}）';
        }
        return '已收到 X 的 HTTPS 响应（${response.statusCode}）。此测试不验证登录、图片或视频。';
      })()
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return '连接测试失败，请检查网络、VPN 或代理地址与端口';
    } finally {
      client.close(force: true);
    }
  }
}
