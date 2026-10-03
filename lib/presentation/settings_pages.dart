import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/storage/storage_service.dart';
import '../core/storage/reading_settings.dart';
import '../core/theme/theme_provider.dart';
import '../core/services/image_cache_maintenance.dart';
import '../core/services/settings_backup.dart';
import '../twitter/auth/app_controller.dart';
import '../core/services/notification_poll.dart';

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});
  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  bool _busy = false;
  String? _error;
  Future<void> _set(String key, bool value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (key == 'notification_enabled' && value) {
        final granted = await NotificationPoll.channel
                .invokeMethod<bool>('requestPermission') ??
            false;
        if (!granted) throw StateError('未授予系统通知权限，请在系统设置中开启');
      }
      await ref.read(storageServiceProvider).setBool(key, value);
      await NotificationPoll.sync();
    } catch (_) {
      if (mounted) setState(() => _error = '无法启用提醒，请检查通知权限和登录状态');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageServiceProvider),
        loggedIn = ref.watch(appControllerProvider).loggedIn;
    return Scaffold(
        appBar: AppBar(title: const Text('订阅消息提醒')),
        body: ListView(children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  '定期读取 X 官方通知；首次读取只建立基线。Android 系统安排至少 15 分钟一次的任务，省电策略可能延迟，无法保证即时通知。')),
          SwitchListTile(
              title: const Text('启用消息提醒'),
              subtitle: loggedIn ? null : const Text('请先登录 X'),
              value: storage.getBool('notification_enabled'),
              onChanged: _busy || !loggedIn
                  ? null
                  : (v) => _set('notification_enabled', v)),
          for (final entry in const {
            'mentions': '提及与回复',
            'likes': '点赞',
            'reposts': '转发',
            'followers': '关注',
            'other': '其他通知'
          }.entries)
            SwitchListTile(
                title: Text(entry.value),
                value: storage.getBool('notification_${entry.key}',
                    defaultValue: true),
                onChanged:
                    _busy ? null : (v) => _set('notification_${entry.key}', v)),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        ]));
  }
}

class ReadingSettingsPage extends ConsumerWidget {
  const ReadingSettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readingProvider),
        notifier = ref.read(readingProvider.notifier);
    return Scaffold(
        appBar: AppBar(title: const Text('帖子与阅读样式')),
        body: ListView(children: [
          for (final entry in const {
            'relativeTime': '相对时间',
            'showYear': '显示年份',
            'showWeekday': '显示星期',
            'showSeconds': '显示秒数',
            'utcTime': '使用 UTC 时间',
            'showSource': '显示发布来源',
            'grokAutoTranslate': '自动显示 Grok 翻译',
            'showBanner': '显示主页背景图',
            'cardBackground': '帖子背景',
            'largeImages': '单图保留图片比例',
            'defaultMutedVideo': '默认静音播放视频',
            'coloredLinks': '链接使用主题色',
            'showSensitive': '直接显示标记为敏感的媒体',
            'saveHistory': '记录本机浏览历史',
          }.entries)
            SwitchListTile(
                title: Text(entry.value),
                subtitle: entry.key == 'grokAutoTranslate'
                    ? const Text('仅在 X 返回可用的中文全文翻译时生效')
                    : entry.key == 'defaultMutedVideo'
                        ? const Text('视频打开时静音；滑动调节音量会恢复声音，仅调整应用内音量')
                        : null,
                value: state[entry.key],
                onChanged: (value) => notifier.set(entry.key, value)),
          for (final entry in const {
            'fontSize': '正文字号',
            'lineHeight': '正文行距',
            'imageRadius': '图片圆角'
          }.entries)
            ListTile(
                title: Text(
                    '${entry.value} ${(state[entry.key] as num).toStringAsFixed(1)}'),
                subtitle: Slider(
                    value: state[entry.key],
                    min: entry.key == 'fontSize'
                        ? 12
                        : entry.key == 'lineHeight'
                            ? 1.1
                            : 0,
                    max: entry.key == 'fontSize'
                        ? 24
                        : entry.key == 'lineHeight'
                            ? 2
                            : 28,
                    onChanged: (value) => notifier.set(entry.key, value))),
        ]));
  }
}

class DisplaySettingsPage extends ConsumerStatefulWidget {
  const DisplaySettingsPage({super.key});
  @override
  ConsumerState<DisplaySettingsPage> createState() =>
      _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends ConsumerState<DisplaySettingsPage> {
  static const _channel = MethodChannel('com.review.x/theme');
  List<dynamic>? _modes;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final modes = await _channel.invokeListMethod<dynamic>('getDisplayModes');
      if (mounted) setState(() => _modes = modes ?? []);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取设备显示模式');
    }
  }

  Future<void> _set(int mode) async {
    try {
      await _channel.invokeMethod('setScreenRefreshRateMode', {'mode': mode});
      await ref.read(themeProvider.notifier).setScreenRefreshRateMode(mode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设备未接受这个显示模式')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(themeProvider).screenRefreshRateMode;
    return Scaffold(
        appBar: AppBar(title: const Text('屏幕刷新率')),
        body: _error != null
            ? Center(child: Text(_error!))
            : _modes == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(children: [
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('选择设备支持的模式。系统省电策略可能覆盖应用请求。')),
                    ListTile(
                        leading: Icon(selected == 0
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off),
                        title: const Text('跟随系统'),
                        onTap: () => _set(0)),
                    for (final mode in _modes!)
                      ListTile(
                          leading: Icon(selected == mode['id']
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off),
                          title: Text(
                              '${mode['width']} × ${mode['height']} · ${(mode['rate'] as num).round()} Hz'),
                          onTap: () => _set(mode['id']))
                  ]));
  }
}

class StorageSettingsPage extends ConsumerStatefulWidget {
  const StorageSettingsPage({super.key});
  @override
  ConsumerState<StorageSettingsPage> createState() =>
      _StorageSettingsPageState();
}

class _StorageSettingsPageState extends ConsumerState<StorageSettingsPage> {
  String _size = '读取中…';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _readSize();
  }

  Future<void> _readSize() async {
    try {
      final bytes = await ImageCacheMaintenance.bytes();
      if (mounted) {
        setState(
            () => _size = '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB');
      }
    } catch (_) {
      if (mounted) setState(() => _size = '暂不可读取');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('存储与缓存')),
      body: ListView(children: [
        ListTile(
            title: const Text('媒体保存目录'),
            subtitle: const Text('图片 Pictures/ReviewX，视频 Movies/ReviewX'),
            trailing: DropdownButton<String>(
                value: ref.watch(readingProvider)['storageFolder'],
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('默认')),
                  DropdownMenuItem(value: 'me', child: Text('按我的账号')),
                  DropdownMenuItem(value: 'author', child: Text('按作者'))
                ],
                onChanged: (v) {
                  if (v != null) {
                    ref.read(readingProvider.notifier).set('storageFolder', v);
                  }
                })),
        ListTile(
            title: const Text('图片磁盘缓存'),
            subtitle: Text('$_size · 退出时保留 · 自动整理上限 512 MiB / 60 天'),
            trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await ImageCacheMaintenance.clear();
                          PaintingBinding.instance.imageCache.clear();
                          await _readSize();
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('缓存清理失败，请稍后重试')));
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: Text(_busy ? '清理中…' : '清理图片'))),
      ]));
}

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(appControllerProvider).client.session?.userId;
    final history = BrowsingHistory(ref.watch(storageServiceProvider));
    return StatefulBuilder(builder: (context, setState) {
      final items = id == null ? <Map<String, dynamic>>[] : history.read(id);
      return Scaffold(
          appBar: AppBar(title: const Text('本机浏览历史'), actions: [
            IconButton(
                tooltip: '清空本机历史',
                icon: const Icon(Icons.delete_outline),
                onPressed: id == null || items.isEmpty
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                                    title: const Text('清空本机历史？'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('取消')),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('清空'))
                                    ]));
                        if (confirmed == true) {
                          await history.clear(id);
                          if (context.mounted) setState(() {});
                        }
                      })
          ]),
          body: items.isEmpty
              ? const Center(child: Text('暂无本机浏览历史'))
              : ListView(children: [
                  for (final item in items)
                    ListTile(
                        title: Text('${item['title']}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${item['author']} · ${item['time']}'
                            .split('.')
                            .first),
                        onTap: () async {
                          final uri = Uri.tryParse('${item['url']}');
                          if (uri != null &&
                              uri.scheme == 'https' &&
                              uri.host == 'x.com') {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        })
                ]));
    });
  }
}

class BackupSettingsPage extends ConsumerStatefulWidget {
  const BackupSettingsPage({super.key});
  @override
  ConsumerState<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends ConsumerState<BackupSettingsPage> {
  static const _secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final _url = TextEditingController(),
      _user = TextEditingController(),
      _password = TextEditingController();
  bool _busy = false;
  String? _status;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data =
          jsonDecode(await _secure.read(key: 'webdav_config') ?? '{}') as Map;
      if (!mounted) return;
      _url.text = '${data['url'] ?? ''}';
      _user.text = '${data['user'] ?? ''}';
      _password.text = '${data['password'] ?? ''}';
    } catch (_) {
      if (mounted) setState(() => _status = '读取 WebDAV 配置失败');
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(bool upload) async {
    if (_busy) return;
    if (!upload) {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('恢复 WebDAV 设置？'),
                  content: const Text('将覆盖本机外观和阅读设置。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('恢复'))
                  ]));
      if (confirm != true) return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final backup = SettingsBackup(ref.read(storageServiceProvider));
      if (upload) {
        await backup.upload(_url.text.trim(), _user.text, _password.text);
      } else {
        await backup.download(_url.text.trim(), _user.text, _password.text);
        ref.read(readingProvider.notifier).reload();
        ref.read(themeProvider.notifier).reload();
      }
      await _secure.write(
          key: 'webdav_config',
          value: jsonEncode({
            'url': _url.text.trim(),
            'user': _user.text,
            'password': _password.text
          }));
      if (mounted) setState(() => _status = upload ? '设置已备份到 WebDAV' : '设置已恢复');
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('WebDAV 设置备份')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('指定已存在的 HTTPS WebDAV 文件夹。备份外观和阅读设置；账号凭据、浏览历史与设备刷新率留在本机。'),
        const SizedBox(height: 16),
        TextField(
            controller: _url,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'HTTPS WebDAV 文件夹')),
        TextField(
            controller: _user,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '用户名')),
        TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '密码')),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: _busy ? null : () => _run(true),
            child: const Text('立即备份')),
        OutlinedButton(
            onPressed: _busy ? null : () => _run(false),
            child: const Text('恢复设置')),
        if (_busy) const LinearProgressIndicator(),
        if (_status != null) Text(_status!),
      ]));
}
