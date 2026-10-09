import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/storage/storage_service.dart';
import '../core/widgets/frosted_app_bar.dart';
import '../core/widgets/app_section_card.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/storage/reading_settings.dart';
import '../core/theme/theme_provider.dart';
import '../core/services/image_cache_maintenance.dart';
import '../core/services/settings_backup.dart';
import '../twitter/auth/app_controller.dart';
import '../core/services/notification_poll.dart';
import 'timeline_page.dart';

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

class ReadingSettingsPage extends ConsumerStatefulWidget {
  const ReadingSettingsPage({super.key});
  @override
  ConsumerState<ReadingSettingsPage> createState() =>
      _ReadingSettingsPageState();
}

class _ReadingSettingsPageState extends ConsumerState<ReadingSettingsPage> {
  final Map<String, int> _lastSliderStep = {};

  int _step(double value) => (value * 10).round();

  Future<void> _saveSlider(String key, double value) async {
    try {
      await ref.read(readingProvider.notifier).set(key, value);
    } catch (_) {
      if (mounted) {
        ref.read(readingProvider.notifier).reload();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置保存失败')));
      }
    } finally {
      _lastSliderStep.remove(key);
    }
  }

  Widget _sliderTile(
      MapEntry<String, String> entry, Map<String, dynamic> state) {
    final storedValue = (state[entry.key] as num).toDouble();
    final value = storedValue;
    final min = entry.key == 'fontSize'
        ? 12.0
        : entry.key == 'lineHeight'
            ? 1.1
            : 0.0;
    final max = entry.key == 'fontSize'
        ? 24.0
        : entry.key == 'lineHeight'
            ? 2.0
            : 28.0;
    final divisions = ((max - min) * 10).round();
    return ListTile(
      title: Text('${entry.value} ${value.toStringAsFixed(1)}'),
      subtitle: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChangeStart: (_) => _lastSliderStep[entry.key] = _step(storedValue),
        onChanged: (next) {
          final step = _step(next);
          if (_lastSliderStep[entry.key] != step) {
            HapticFeedbackUtil.selection(bypassCooldown: true);
            _lastSliderStep[entry.key] = step;
          }
          ref.read(readingProvider.notifier).preview(entry.key, next);
        },
        onChangeEnd: (next) => _saveSlider(entry.key, next),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            'grokAutoTranslate': '自动翻译外文推文',
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
                value: state[entry.key],
                onChanged: (value) {
                  HapticFeedbackUtil.selection();
                  notifier.set(entry.key, value);
                }),
          ListTile(
            title: const Text('默认视频清晰度'),
            subtitle: Text(_videoQualityLabel(
                state['videoQuality'] as String? ?? 'balanced')),
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: () => _selectVideoQuality(context, notifier,
                state['videoQuality'] as String? ?? 'balanced'),
          ),
          for (final entry in const {
            'fontSize': '正文字号',
            'lineHeight': '正文行距',
            'imageRadius': '图片圆角'
          }.entries)
            _sliderTile(entry, state),
        ]));
  }

  static String _videoQualityLabel(String quality) {
    switch (quality) {
      case 'high':
        return '最高画质 (1080p/原画)';
      case 'data_saver':
        return '省流模式 (480p/360p)';
      case 'balanced':
      default:
        return '优先流畅 (720p/智能推荐)';
    }
  }

  Future<void> _selectVideoQuality(
      BuildContext context, ReadingNotifier notifier, String current) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  '默认视频清晰度',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                title: const Text('优先流畅 (720p/智能推荐)'),
                subtitle: const Text('大幅降低缓冲与卡顿，秒开播放，画质适合移动屏幕'),
                trailing: current == 'balanced'
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, 'balanced'),
              ),
              ListTile(
                title: const Text('最高画质 (1080p/原画)'),
                subtitle: const Text('保持最高码率，需要极佳的网络带宽与代理环境'),
                trailing: current == 'high'
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, 'high'),
              ),
              ListTile(
                title: const Text('省流模式 (480p/360p)'),
                subtitle: const Text('消耗流量极低，弱网环境下播放更顺畅'),
                trailing: current == 'data_saver'
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, 'data_saver'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null && selected != current) {
      HapticFeedbackUtil.selection();
      await notifier.set('videoQuality', selected);
    }
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
            subtitle: Text(_size),
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
      final appBar = buildFrostedAppBar(
        context,
        title: const Text('本机浏览历史'),
        actions: [
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
        ],
      );
      final topChromeHeight =
          MediaQuery.paddingOf(context).top + appBar.preferredSize.height;
      return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: appBar,
          body: items.isEmpty
              ? const Center(child: Text('暂无本机浏览历史'))
              : ListView(
                  padding: EdgeInsets.only(top: topChromeHeight),
                  children: [
                      for (final item in items)
                        ListTile(
                            title: Text('${item['title']}',
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${item['author']} · ${item['time']}'
                                .split('.')
                                .first),
                            onTap: () {
                              final postId = '${item['id']}';
                              if (!RegExp(r'^\d{1,30}$').hasMatch(postId)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('这条历史记录没有有效的帖子编号')));
                                return;
                              }
                              Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                      builder: (_) => PostDetailPage.fromId(
                                          postId: postId)));
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(title, style: theme.textTheme.titleSmall),
            ),
            AppSectionCard(margin: EdgeInsets.zero, child: child),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 设置备份')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.paddingOf(context).bottom + 24),
        children: [
          section(
            '连接信息',
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '指定已存在的 HTTPS WebDAV 文件夹。备份外观和阅读设置；账号凭据、浏览历史与设备刷新率留在本机。',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _url,
                      enabled: !_busy,
                      decoration:
                          const InputDecoration(labelText: 'HTTPS WebDAV 文件夹')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _user,
                      enabled: !_busy,
                      decoration: const InputDecoration(labelText: '用户名')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: '密码')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          section(
            '设置同步',
            Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('立即备份'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  enabled: !_busy,
                  onTap: _busy ? null : () => _run(true),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('恢复设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  enabled: !_busy,
                  onTap: _busy ? null : () => _run(false),
                ),
                if (_busy) ...[
                  const Divider(height: 1),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                ],
                if (_status != null) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _status!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
