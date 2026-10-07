import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/widgets/cached_network_image.dart';
import '../twitter/auth/app_controller.dart';
import 'discovery_pages.dart';
import 'login_page.dart';
import 'settings_pages.dart';
import 'timeline_page.dart';

/// X-specific version of Review's compact account drawer.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final user = controller.me;
    final theme = Theme.of(context);
    final navigator = Navigator.of(context);
    final name = user?.name ?? (controller.loggedIn ? 'X 已登录' : '未登录 / 访客');

    void open(Widget page) {
      navigator.pop();
      navigator.push(MaterialPageRoute<void>(builder: (_) => page));
    }

    void openAccountPage(Widget page) {
      open(controller.loggedIn ? page : const LoginPage());
    }

    Future<void> openProfile() async {
      final messenger = ScaffoldMessenger.of(context);
      navigator.pop();
      if (!controller.loggedIn) {
        navigator
            .push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
        return;
      }
      if (controller.me == null) {
        if (controller.busy) {
          messenger
              .showSnackBar(const SnackBar(content: Text('账号正在处理中，请稍后再试')));
          return;
        }
        try {
          await controller.validateSession();
        } catch (error) {
          if (navigator.mounted) {
            messenger.showSnackBar(SnackBar(content: Text('$error')));
          }
          return;
        }
      }
      final profile = controller.me;
      if (profile != null && navigator.mounted) {
        navigator.push(MaterialPageRoute<void>(
            builder: (_) => ProfilePage(user: profile)));
      }
    }

    Widget drawerItem({
      required IconData icon,
      required String title,
      required VoidCallback onTap,
    }) {
      return ListTile(
        leading: Icon(icon, size: 22),
        title: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        visualDensity: VisualDensity.compact,
        onTap: onTap,
      );
    }

    return Drawer(
      width: 280,
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: openProfile,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipOval(
                        child: user?.avatar.isNotEmpty == true
                            ? CachedNetworkImage(user!.avatar,
                                width: 64, height: 64, fit: BoxFit.cover)
                            : Container(
                                width: 64,
                                height: 64,
                                color: theme.colorScheme.secondaryContainer,
                                alignment: Alignment.center,
                                child: Icon(Icons.person_rounded,
                                    size: 36,
                                    color: theme
                                        .colorScheme.onSecondaryContainer)),
                      ),
                      const SizedBox(height: 14),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16.5, fontWeight: FontWeight.bold)),
                      if (user != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('@${user.handle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  drawerItem(
                    icon: Icons.bookmarks_outlined,
                    title: '书签',
                    onTap: () => openAccountPage(const BookmarksPage()),
                  ),
                  drawerItem(
                    icon: Icons.notifications_outlined,
                    title: '通知',
                    onTap: () => openAccountPage(const NotificationsPage()),
                  ),
                  drawerItem(
                    icon: Icons.history_rounded,
                    title: '浏览历史',
                    onTap: () => open(const HistoryPage()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
