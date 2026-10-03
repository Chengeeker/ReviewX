import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../twitter/api/twitter_client.dart';
import '../twitter/auth/app_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _cookie = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _visible = false;

  Future<void> _login() async {
    if (_busy || ref.read(appControllerProvider).busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(appControllerProvider);
    try {
      await controller.login(_cookie.text);
      _cookie.clear();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is TwitterFailure
            ? '${controller.loginStage}：${error.message}'
            : error is FormatException
                ? 'Cookie 格式不正确，请提供包含 auth_token 和 ct0 的 Cookie。'
                : '登录验证失败，请检查网络或安全存储后重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cookie.clear();
    _cookie.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy || ref.watch(appControllerProvider).busy;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Cookie 登录 X')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.key, size: 48),
            const SizedBox(height: 16),
            const Text('在浏览器中登录 X，再将该账号的 Cookie 粘贴到下方。',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Text(
                '获取方式：在电脑浏览器打开 x.com 并登录，打开开发者工具的 Network（网络），刷新页面，选择发送到 x.com 或 api.x.com 的请求，在请求头中复制 Cookie 的值。只粘贴值，不要包含“Cookie:”或其他请求头。'),
            const SizedBox(height: 12),
            const Text(
                '必须包含 auth_token 和 ct0，建议同时包含 twid。Cookie 等同账号凭据，请勿发给他人。验证通过后仅保存在本机安全存储中，不进入设置备份。'),
            const SizedBox(height: 24),
            TextField(
              controller: _cookie,
              enabled: !busy,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: 'X Cookie',
                hintText: 'auth_token=…; ct0=…; twid=…',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _visible ? '隐藏 Cookie' : '显示 Cookie',
                  onPressed:
                      busy ? null : () => setState(() => _visible = !_visible),
                  icon:
                      Icon(_visible ? Icons.visibility_off : Icons.visibility),
                ),
              ),
              onSubmitted: busy ? null : (_) => _login(),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: busy ? null : _login,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: Text(busy ? '正在验证账号…' : '验证并登录'),
            ),
          ],
        ),
      ),
    );
  }
}
