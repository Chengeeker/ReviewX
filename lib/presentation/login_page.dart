import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../twitter/api/twitter_client.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/auth/x_web_auth.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with WidgetsBindingObserver {
  final _cookie = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _showCookie = false;
  bool _importCookie = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(XWebAuth.recordFlutterLifecycle(state.name));
  }

  Future<void> _copyLoginDiagnostics() async {
    final diagnostics = await XWebAuth.getLoginDiagnostics();
    if (!mounted) return;
    if (diagnostics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有登录诊断记录')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录诊断已复制（不含 Cookie 或密码）')),
      );
    }
  }

  Future<void> _loginWithX() async {
    if (_busy || ref.read(appControllerProvider).busy) return;
    FocusScope.of(context).unfocus();
    await _runLogin(() async {
      final completed = await ref.read(appControllerProvider).loginWithWeb();
      if (!mounted) return;
      if (completed) Navigator.pop(context);
    });
  }

  Future<void> _loginWithCookie() async {
    if (_busy || ref.read(appControllerProvider).busy) return;
    FocusScope.of(context).unfocus();
    await _runLogin(() async {
      final controller = ref.read(appControllerProvider);
      await controller.login(_cookie.text);
      _cookie.clear();
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _runLogin(Future<void> Function() login) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(appControllerProvider);
    try {
      await login();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is XWebAuthException
            ? error.message
            : error is TwitterFailure
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
    WidgetsBinding.instance.removeObserver(this);
    _cookie.clear();
    _cookie.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy || ref.watch(appControllerProvider).busy;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colors.outlineVariant),
    );

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_importCookie ? 'Cookie 导入' : '账号登录'),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                        _importCookie = !_importCookie;
                        _error = null;
                      }),
              child: Text(_importCookie ? '账号登录' : 'Cookie 导入'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
          children: [
            if (_error != null) ...[
              Text(_error!,
                  style: TextStyle(color: colors.error),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
            ],
            if (_importCookie) ...[
              Text(
                '粘贴 X 会话 Cookie。至少包含 auth_token 和 ct0；验证通过后仅保存在本机加密存储中。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('cookieField'),
                controller: _cookie,
                enabled: !busy,
                obscureText: !_showCookie,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  labelText: 'X Cookie',
                  hintText: 'auth_token=…; ct0=…; twid=…',
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                  focusedBorder: fieldBorder.copyWith(
                    borderSide: BorderSide(color: colors.primary, width: 2),
                  ),
                  suffixIcon: IconButton(
                    tooltip: _showCookie ? '隐藏 Cookie' : '显示 Cookie',
                    onPressed: busy
                        ? null
                        : () => setState(() => _showCookie = !_showCookie),
                    icon: Icon(
                        _showCookie ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
                onSubmitted: busy ? null : (_) => _loginWithCookie(),
              ),
              const SizedBox(height: 16),
              _primaryButton(
                busy: busy,
                label: busy ? '正在验证账号…' : '验证并登录',
                onPressed: _loginWithCookie,
              ),
            ] else ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: colors.primaryContainer,
                        child: Icon(Icons.open_in_browser,
                            color: colors.onPrimaryContainer, size: 28),
                      ),
                      const SizedBox(height: 20),
                      Text('使用 X 官方页面登录',
                          style: theme.textTheme.titleLarge,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(
                        '账号、密码和安全验证都在 X 页面完成。ReviewX 不会收集或保存你的密码；登录成功后会验证会话并返回应用。',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _primaryButton(
                        busy: busy,
                        label: busy ? '正在打开 X…' : '前往 X 登录',
                        onPressed: _loginWithX,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: busy ? null : _copyLoginDiagnostics,
              icon: const Icon(Icons.content_copy_outlined),
              label: const Text('复制登录诊断（不含账号凭据）'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton({
    required bool busy,
    required String label,
    required VoidCallback onPressed,
  }) =>
      SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(shape: const StadiumBorder()),
          child: busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(label),
        ),
      );
}
