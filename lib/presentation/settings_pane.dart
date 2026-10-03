import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/widgets/app_section_card.dart';
import '../core/theme/theme_provider.dart';
import '../twitter/auth/app_controller.dart';
import 'login_page.dart';
import 'settings_pages.dart';
import 'theme_settings_page.dart';

const _appVersion = '0.8.1';

/// Review-style grouped settings, with X-specific account actions retained.
class SettingsPane extends ConsumerWidget {
  const SettingsPane({super.key});

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
                onTap: () => showLicensePage(
                  context: dialogContext,
                  applicationName: 'ReviewX',
                  applicationVersion: _appVersion,
                ),
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
                      Icon(Icons.description_outlined,
                          color: colorScheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '开源许可与来源',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'MIT 许可 · 第三方来源见许可声明',
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
      Color? iconColor,
      Color? titleColor,
    }) =>
        ListTile(
          leading: Icon(icon, color: iconColor ?? colorScheme.primary),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(subtitle, style: const TextStyle(fontSize: 12.5)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        );

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomClearance),
      children: [
        AppSectionCard(
          child: Column(
            children: [
              row(
                icon: Icons.palette_outlined,
                title: '个性化',
                subtitle: '明暗、色彩、字重、导航、屏幕与触感',
                onTap: () => open(const ThemeSettingsPage()),
              ),
              const Divider(height: 1, indent: 56),
              row(
                icon: Icons.article_outlined,
                title: '帖子与阅读样式',
                subtitle: '时间、正文、链接、卡片与媒体显示',
                onTap: () => open(const ReadingSettingsPage()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppSectionCard(
          child: row(
            icon: Icons.notifications_active_outlined,
            title: '订阅消息提醒',
            subtitle: '管理后台提醒类型与系统通知权限',
            onTap: () => open(const NotificationSettingsPage()),
          ),
        ),
        const SizedBox(height: 14),
        AppSectionCard(
          child: Column(
            children: [
              row(
                icon: Icons.folder_open_outlined,
                title: '存储与缓存',
                subtitle: '媒体保存目录、磁盘缓存和清理',
                onTap: () => open(const StorageSettingsPage()),
              ),
              const Divider(height: 1, indent: 56),
              row(
                icon: Icons.cloud_sync_outlined,
                title: 'WebDAV 设置备份',
                subtitle: '仅备份外观与阅读设置，不含账号凭据',
                onTap: () => open(const BackupSettingsPage()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppSectionCard(
          child: Column(
            children: [
              row(
                icon: controller.loggedIn
                    ? Icons.person_outline_rounded
                    : Icons.login_rounded,
                title: controller.me?.name ??
                    (controller.loggedIn ? 'X 已登录' : '登录 X 账号'),
                subtitle: controller.me == null
                    ? '使用 X Cookie 验证并登录'
                    : '@${controller.me!.handle}',
                onTap: () => open(const LoginPage()),
              ),
              if (controller.loggedIn) ...[
                const Divider(height: 1, indent: 56),
                row(
                  icon: Icons.verified_user_outlined,
                  title: '验证登录状态',
                  subtitle: controller.busy ? '正在验证账号…' : '通过 X 官方接口确认当前账号',
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
              ],
              const Divider(height: 1, indent: 56),
              row(
                icon: Icons.info_outline_rounded,
                title: '关于 ReviewX',
                subtitle: '版本 $_appVersion',
                onTap: () => _showAboutDialog(context),
              ),
              if (controller.loggedIn) ...[
                const Divider(height: 1, indent: 56),
                row(
                  icon: Icons.logout_rounded,
                  title: '退出登录',
                  subtitle: '清除本机安全存储中的 X 会话',
                  iconColor: colorScheme.error,
                  titleColor: colorScheme.error,
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
            ],
          ),
        ),
      ],
    );
  }
}
