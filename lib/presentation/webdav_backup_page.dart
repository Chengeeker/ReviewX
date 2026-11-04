import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/services/settings_backup.dart';
import '../core/storage/storage_service.dart';
import '../core/storage/reading_settings.dart';
import '../core/theme/theme_provider.dart';
import '../core/widgets/frosted_app_bar.dart';
import '../core/utils/haptic_feedback_util.dart';

class BackupSettingsPage extends ConsumerStatefulWidget {
  const BackupSettingsPage({super.key});
  @override
  ConsumerState<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends ConsumerState<BackupSettingsPage> {
  static const _secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController(),
      _usernameController = TextEditingController(),
      _passwordController = TextEditingController(),
      _dirController = TextEditingController(text: 'ReviewX');
  bool _isTesting = false,
      _isBackingUp = false,
      _isRestoring = false,
      _loadingConfig = true;
  bool _includeCredentials = false;
  bool get _isBusy =>
      _loadingConfig || _isTesting || _isBackingUp || _isRestoring;
  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final data =
          jsonDecode(await _secure.read(key: 'webdav_config') ?? '{}') as Map;
      if (!mounted) return;
      _urlController.text = data['url'] as String? ?? '';
      _usernameController.text = data['user'] as String? ?? '';
      _passwordController.text = data['password'] as String? ?? '';
      // Installed versions stored the final folder URL without a directory field.
      _dirController.text = data['directory'] as String? ??
          (data.containsKey('url') ? '' : 'ReviewX');
    } catch (_) {
      if (mounted) _message('读取 WebDAV 配置失败');
    } finally {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  Future<void> _saveConfig() => _secure.write(
      key: 'webdav_config',
      value: jsonEncode({
        'url': _urlController.text.trim(),
        'user': _usernameController.text.trim(),
        'password': _passwordController.text,
        'directory': _dirController.text.trim(),
      }));
  String get _endpoint {
    final raw = _urlController.text.trim();
    final uri = Uri.parse(raw.endsWith('/') ? raw : '$raw/');
    final directory = _dirController.text.trim();
    if (directory == '.' ||
        directory == '..' ||
        directory.contains('/') ||
        directory.contains('\\')) {
      throw const FormatException('备份文件夹名称不能包含路径分隔符');
    }
    return directory.isEmpty
        ? uri.toString()
        : uri.resolve('${Uri.encodeComponent(directory)}/').toString();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _testConnection() => _run(test: true);
  Future<void> _performBackup() => _run();
  Future<void> _performRestore() async {
    if (_isBusy || !_formKey.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('从 WebDAV 恢复备份？'),
              content: const Text(
                  '恢复备份将覆盖备份中包含的设置和历史。若云端是全量备份，还会替换 X 登录凭据及 WebDAV 密码；全量安全备份保留本机登录凭据。恢复后请重启应用以应用全部数据，是否继续？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('确定恢复'))
              ],
            ));
    if (confirmed == true && mounted) await _run(restore: true);
  }

  Future<void> _run({bool test = false, bool restore = false}) async {
    if (_isBusy || !_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = test;
      _isRestoring = restore;
      _isBackingUp = !test && !restore;
    });
    try {
      final endpoint = _endpoint;
      await _saveConfig();
      final service = SettingsBackup(ref.read(storageServiceProvider));
      if (test) {
        await service.testConnection(_urlController.text.trim(),
            _usernameController.text.trim(), _passwordController.text);
      } else if (restore) {
        await service.download(endpoint, _usernameController.text.trim(),
            _passwordController.text);
        if (!mounted) return;
        ref.read(readingProvider.notifier).reload();
        ref.read(themeProvider.notifier).reload();
        await _loadConfig();
      } else {
        await service.upload(
            endpoint, _usernameController.text.trim(), _passwordController.text,
            includeCredentials: _includeCredentials,
            directory: _dirController.text.trim());
      }
      if (mounted) {
        _message(test
            ? 'WebDAV 服务器连接成功！'
            : restore
                ? '备份已成功恢复，重启应用可应用全部设置与登录数据'
                : '已成功备份到 WebDAV 云盘！');
      }
    } catch (_) {
      if (mounted) {
        _message(test
            ? '连接失败，请检查服务器地址、账号与授权密码'
            : restore
                ? '恢复失败，备份格式无效或下载、写入失败'
                : '备份提交未确认，请检查连接状态和云端文件');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _isBackingUp = false;
          _isRestoring = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildFrostedAppBar(
        context,
        title: const Text(
          'WebDAV 云端备份与恢复',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + kToolbarHeight + 14,
            16,
            14,
          ),
          children: [
            // 1. Info Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cloud_sync_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '备份内容',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '备份应用设置、搜索与浏览历史等本地数据，不包含图片和视频缓存。',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            AbsorbPointer(
              absorbing: _isBusy,
              child: _BackupSectionCard(
                child: Column(
                  children: [
                    _BackupChoiceTile<bool>(
                      title: '全量安全备份',
                      summary: 'Cookie、Token 和 WebDAV 密码不会上传。',
                      value: false,
                      groupValue: _includeCredentials,
                      onSelected: () =>
                          setState(() => _includeCredentials = false),
                    ),
                    _BackupChoiceTile<bool>(
                      title: '全量备份',
                      summary:
                          '同时上传 Cookie、Token 和 WebDAV 密码。备份文件含明文凭据，请妥善保管云盘及历史备份。',
                      value: true,
                      groupValue: _includeCredentials,
                      onSelected: () =>
                          setState(() => _includeCredentials = true),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Configuration Card
            _BackupSectionCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WebDAV 服务器配置',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      enabled: !_isBusy,
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: '服务器 URL',
                        hintText: '例如: https://dav.jianguoyun.com/dav/',
                        prefixIcon: Icon(Icons.link_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return '请输入 WebDAV 服务器地址';
                        }
                        final uri = Uri.tryParse(v.trim());
                        if (uri == null ||
                            uri.scheme != 'https' ||
                            uri.host.isEmpty ||
                            uri.userInfo.isNotEmpty ||
                            uri.hasQuery ||
                            uri.hasFragment) {
                          return '请输入无查询参数的 HTTPS 地址';
                        }
                        final lower = v.trim().toLowerCase();
                        if (lower.startsWith('http://') &&
                            !lower.startsWith('http://127.0.0.1') &&
                            !lower.startsWith('http://localhost')) {
                          return '为了安全，WebDAV 请使用加密的 https:// 协议';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      enabled: !_isBusy,
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: '账号 / 邮箱',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      enabled: !_isBusy,
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '应用密码 / Token',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '请输入密码或授权 Token'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      enabled: !_isBusy,
                      controller: _dirController,
                      decoration: const InputDecoration(
                        labelText: '备份文件夹名称',
                        hintText: '默认: ReviewX',
                        prefixIcon: Icon(Icons.folder_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: _isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.wifi_tethering_rounded,
                                size: 18,
                              ),
                        label: Text(_isTesting ? '正在测试连接...' : '测试服务器连接'),
                        onPressed: _isBusy ? null : _testConnection,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Actions Section
            _BackupSectionCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '云端备份与还原操作',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: _isBackingUp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload_rounded),
                            label: Text(_isBackingUp ? '正在上传...' : '立即备份到云端'),
                            onPressed: _isBusy ? null : _performBackup,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: _isRestoring
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download_rounded),
                            label: Text(_isRestoring ? '正在拉取...' : '从云端恢复备份'),
                            onPressed: _isBusy ? null : _performRestore,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Low-emphasis, flush surface for grouped settings and utility actions.
class _BackupSectionCard extends StatelessWidget {
  final Widget child;

  const _BackupSectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.surface == Colors.black
        ? scheme.surfaceContainer
        : scheme.surfaceContainerLow;
    return Card(
      margin: EdgeInsets.zero,
      color: color,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide.none,
      ),
      child: child,
    );
  }
}

/// One choice row rendered in the active Review design language.
class _BackupChoiceTile<T> extends StatelessWidget {
  const _BackupChoiceTile({
    super.key,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onSelected,
    this.summary,
  });

  final String title;
  final String? summary;
  final T value;
  final T groupValue;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return RadioGroup<T>(
      groupValue: groupValue,
      onChanged: (selectedValue) {
        if (selectedValue == null || selectedValue == groupValue) return;
        HapticFeedbackUtil.light();
        onSelected();
      },
      child: RadioListTile<T>(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        title: Text(
          title,
          style: theme.listTileTheme.titleTextStyle?.copyWith(
            fontSize: 16,
            color: colorScheme.onSurface,
          ),
        ),
        subtitle: summary == null
            ? null
            : Text(
                summary!,
                style: theme.listTileTheme.subtitleTextStyle?.copyWith(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
        value: value,
      ),
    );
  }
}
