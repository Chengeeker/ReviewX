import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/widgets/app_section_card.dart';
import '../core/theme/theme_provider.dart';
import '../twitter/auth/app_controller.dart';
import 'login_page.dart';
import 'settings_pages.dart';
import 'theme_settings_page.dart';
import 'network_settings_page.dart';

const _appVersion = '1.0.6';

/// Review-style grouped settings, with X-specific account actions retained.
class SettingsPane extends ConsumerWidget {
  const SettingsPane({super.key, this.topChromeHeight = 0});

  final double topChromeHeight;

  void _showAboutDialog(BuildContext context) {
    HapticFeedbackUtil.light();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/branding/icon13.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'ReviewX',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'v$_appVersion',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '面向 X/Twitter 的 Material 3 客户端',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAboutItem(
                    Icons.dynamic_feed_outlined,
                    '浏览推荐与关注时间线、探索趋势、帖子详情和用户主页',
                    colorScheme,
                  ),
                  const SizedBox(height: 8),
                  _buildAboutItem(
                    Icons.search_rounded,
                    '探索趋势并搜索帖子、用户、图片和视频，也可查看通知',
                    colorScheme,
                  ),
                  const SizedBox(height: 8),
                  _buildAboutItem(
                    Icons.photo_library_outlined,
                    '查看媒体、管理书签，并发布文字帖子、回复和引用',
                    colorScheme,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final uri =
                      Uri.parse('https://github.com/Chengeeker/ReviewX');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.chevron_left_slash_chevron_right,
                          color: colorScheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'GitHub 开源地址',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'github.com/Chengeeker/ReviewX',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.open_in_new_rounded,
                          size: 16, color: colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text('我知道了'),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
  }

  Widget _buildAboutItem(IconData icon, String text, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final useFloatingNavBar = ref.watch(themeProvider).useFloatingNavBar;
    final mediaPadding = MediaQuery.of(context).padding;
    final bottomClearance = useFloatingNavBar
        ? 64.0 +
            (mediaPadding.bottom > 0 ? 6.0 : 14.0) +
            mediaPadding.bottom +
            12.0
        : 24.0;

    void open(Widget page) {
      HapticFeedbackUtil.light();
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    Widget row({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback? onTap,
      Widget? leading,
    }) =>
        ListTile(
          leading: leading ?? Icon(icon, size: 24),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: Icon(Icons.chevron_right_rounded,
              size: 24, color: colorScheme.onSurfaceVariant),
          onTap: onTap,
        );

    Widget section(String title, List<Widget> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
              ),
            ),
            AppSectionCard(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    items[i],
                  ],
                ],
              ),
            ),
          ],
        );

    final accountId = controller.me?.id ?? controller.client.session?.userId;
    return ListView(
      padding:
          EdgeInsets.fromLTRB(16, topChromeHeight + 20, 16, bottomClearance),
      children: [
        section('偏好与功能', [
          row(
            icon: Icons.palette_outlined,
            title: '个性化',
            onTap: () => open(const ThemeSettingsPage()),
          ),
          row(
            icon: Icons.article_outlined,
            title: '帖子与阅读样式',
            onTap: () => open(const ReadingSettingsPage()),
          ),
          row(
            icon: Icons.language_outlined,
            title: '网络设置',
            onTap: () => open(const NetworkSettingsPage()),
          ),
          row(
            icon: Icons.notifications_active_outlined,
            title: '订阅消息提醒',
            onTap: () => open(const NotificationSettingsPage()),
          ),
        ]),
        const SizedBox(height: 32),
        section('存储与备份', [
          row(
            icon: Icons.folder_open_outlined,
            title: '存储与缓存',
            onTap: () => open(const StorageSettingsPage()),
          ),
          row(
            icon: Icons.cloud_sync_outlined,
            title: 'WebDAV 设置备份',
            onTap: () => open(const BackupSettingsPage()),
          ),
        ]),
        const SizedBox(height: 32),
        section('账号与应用', [
          row(
            icon: Icons.person_outline_rounded,
            title: controller.loggedIn
                ? (controller.me?.name ?? 'X 账号')
                : '登录 X 账号',
            subtitle: controller.loggedIn && accountId != null
                ? 'UID：$accountId'
                : null,
            onTap: controller.busy
                ? null
                : () => controller.loggedIn
                    ? open(const AccountSettingsPage())
                    : open(const LoginPage()),
          ),
          row(
            icon: Icons.info_outline_rounded,
            title: '关于 ReviewX',
            onTap: () => _showAboutDialog(context),
          ),
        ]),
      ],
    );
  }
}

class AccountSettingsPage extends ConsumerWidget {
  const AccountSettingsPage({super.key});

  void _showExportCookie(BuildContext context, AppController controller) {
    final session = controller.client.session;
    if (session == null) return;
    HapticFeedbackUtil.light();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      builder: (sheetContext) => Consumer(builder: (_, ref, __) {
        final current = ref.watch(appControllerProvider);
        final active = identical(current.client.session, session);
        return SafeArea(
            child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text('导出 Cookie',
                        style: Theme.of(sheetContext).textTheme.titleLarge)),
                IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close)),
              ]),
              Text(active
                  ? (current.me == null
                      ? '当前 X 账号'
                      : '${current.me!.name} · @${current.me!.handle}')
                  : '登录账号已变更，请重新打开导出'),
              const SizedBox(height: 12),
              if (active)
                AppSectionCard(
                    child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(session.cookie,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13)),
                )),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: !active
                    ? null
                    : () async {
                        if (!identical(controller.client.session, session)) {
                          return;
                        }
                        try {
                          await Clipboard.setData(
                              ClipboardData(text: session.cookie));
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('已复制 Cookie 到剪贴板')));
                          }
                        } catch (_) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(content: Text('复制失败，请重试')));
                          }
                        }
                      },
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('复制全部'),
              ),
            ],
          ),
        ));
      }),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final colors = Theme.of(context).colorScheme;
    final user = controller.me;
    final accountId = user?.id ?? controller.client.session?.userId;

    return Scaffold(
      appBar: AppBar(title: const Text('账号管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSectionCard(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: colors.surfaceContainerHighest,
                foregroundImage: user?.avatar.isNotEmpty == true
                    ? NetworkImage(user!.avatar)
                    : null,
                child: user?.avatar.isNotEmpty == true
                    ? null
                    : Icon(Icons.person_outline,
                        color: colors.onSurfaceVariant),
              ),
              title: Text(user?.name ?? 'X 账号'),
              subtitle: accountId == null ? null : Text('UID：$accountId'),
            ),
          ),
          const SizedBox(height: 24),
          AppSectionCard(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_all_rounded, size: 24),
                  title: const Text('导出 Cookie'),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 24, color: colors.onSurfaceVariant),
                  onTap: () => _showExportCookie(context, controller),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined, size: 24),
                  title: const Text('验证登录状态'),
                  subtitle: controller.busy ? const Text('正在验证账号…') : null,
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 24, color: colors.onSurfaceVariant),
                  onTap: controller.busy
                      ? null
                      : () async {
                          HapticFeedbackUtil.light();
                          try {
                            await controller.validateSession();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('X 已确认当前登录请求有效')),
                              );
                            }
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$error')),
                              );
                            }
                          }
                        },
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      Icon(Icons.logout_rounded, size: 24, color: colors.error),
                  title: Text('退出登录', style: TextStyle(color: colors.error)),
                  onTap: controller.busy
                      ? null
                      : () async {
                          HapticFeedbackUtil.light();
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('退出 X 账号？'),
                              content: const Text('这会清除本机登录信息。'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('退出'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          try {
                            await controller.logout();
                            if (context.mounted) Navigator.pop(context);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('清除登录信息失败，请重试')),
                              );
                            }
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
