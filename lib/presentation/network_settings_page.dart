import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/network_routing.dart';
import '../core/storage/storage_service.dart';

class NetworkSettingsPage extends ConsumerStatefulWidget {
  const NetworkSettingsPage({super.key});
  @override
  ConsumerState<NetworkSettingsPage> createState() =>
      _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends ConsumerState<NetworkSettingsPage> {
  final _form = GlobalKey<FormState>();
  late ConnectionMode _mode;
  late final TextEditingController _host, _port;
  bool _busy = false;
  String? _result;
  @override
  void initState() {
    super.initState();
    final config = NetworkConfig.read(ref.read(storageServiceProvider));
    _mode = config.mode;
    _host = TextEditingController(text: config.host);
    _port =
        TextEditingController(text: config.port == 0 ? '' : '${config.port}');
  }

  NetworkConfig get _draft => NetworkConfig(
      mode: _mode,
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? 0);
  Future<void> _perform(bool test) async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final config = _draft;
      if (test) {
        final message = await NetworkRouting.test(config);
        if (mounted) setState(() => _result = message);
      } else {
        await config.save(ref.read(storageServiceProvider));
        if (mounted) setState(() => _result = '已保存，完全关闭应用后重新打开生效。');
      }
    } catch (_) {
      if (mounted) setState(() => _result = '操作失败，请检查输入后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('网络设置')),
        body: Form(
            key: _form,
            child: ListView(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, MediaQuery.paddingOf(context).bottom + 24),
                children: [
                  const Text('连接方式',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ConnectionMode>(
                    initialValue: _mode,
                    items: const [
                      DropdownMenuItem(
                          value: ConnectionMode.automatic, child: Text('自动')),
                      DropdownMenuItem(
                          value: ConnectionMode.direct, child: Text('直连')),
                      DropdownMenuItem(
                          value: ConnectionMode.manual, child: Text('手动代理'))
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                              _mode = value!;
                              _result = null;
                            }),
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Text(switch (_mode) {
                    ConnectionMode.automatic =>
                      '启动时读取系统静态 HTTP 代理；Flutter 请求、视频和 X 登录网页使用系统网络路由。VPN 由系统处理，不支持 PAC 自动代理脚本。',
                    ConnectionMode.direct =>
                      'Flutter 请求、视频和 X 登录网页不使用 HTTP 代理。手机已开启的 VPN 仍会影响连接，不会绕过 VPN。',
                    ConnectionMode.manual =>
                      'Flutter 请求、视频和 X 登录网页使用此 HTTP 代理（支持 HTTPS CONNECT）；代理失败时不会回退直连。代理软件需保持运行。',
                  }),
                  if (_mode == ConnectionMode.manual) ...[
                    const SizedBox(height: 20),
                    TextFormField(
                        controller: _host,
                        enabled: !_busy,
                        autocorrect: false,
                        onChanged: (_) => setState(() => _result = null),
                        decoration: const InputDecoration(
                            labelText: '代理地址',
                            hintText: '例如 127.0.0.1',
                            border: OutlineInputBorder()),
                        validator: (value) {
                          try {
                            NetworkConfig(
                                    mode: ConnectionMode.manual,
                                    host: _host.text.trim(),
                                    port: 1)
                                .validate();
                          } on FormatException catch (e) {
                            return e.message.toString();
                          }
                          return null;
                        }),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _port,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() => _result = null),
                        decoration: const InputDecoration(
                            labelText: '端口',
                            hintText: '填写代理软件提供的 HTTP 端口',
                            border: OutlineInputBorder()),
                        validator: (value) {
                          final port = int.tryParse(value ?? '');
                          return port == null || port < 1 || port > 65535
                              ? '请输入 1–65535 的端口'
                              : null;
                        }),
                    const SizedBox(height: 12),
                    const Text(
                        '目前支持主机名或 IPv4 地址、无需认证的 HTTP 代理。不支持 SOCKS、代理账号密码或机场订阅链接。'),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                      '设置用于应用内 API、图片、视频、下载和 WebDAV。外部浏览器遵循自身网络设置。保存后下次启动生效；仅切到后台不会应用新设置。'),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    OutlinedButton.icon(
                        onPressed: _busy ? null : () => _perform(true),
                        icon: const Icon(Icons.network_check),
                        label: const Text('测试连接')),
                    FilledButton(
                        onPressed: _busy ? null : () => _perform(false),
                        child: const Text('保存')),
                  ]),
                  if (_busy)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: LinearProgressIndicator()),
                  if (_result != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_result!)),
                ])),
      );
}
