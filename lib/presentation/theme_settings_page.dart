import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_provider.dart';
import '../core/utils/app_dialog.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/widgets/app_section_card.dart';
import 'settings_pages.dart';

/// 个性化设置页面 (明暗模式、色彩方案、字体粗细、导航布局、屏幕显示与触感)
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  void _showFontWeightDialog(
      BuildContext context, WidgetRef ref, ThemeState themeState) {
    HapticFeedbackUtil.light();
    final colorScheme = Theme.of(context).colorScheme;

    const options = [
      {'label': '偏细', 'delta': -100},
      {'label': '默认', 'delta': 0},
      {'label': '中等', 'delta': 100},
      {'label': '偏粗', 'delta': 200},
      {'label': '加粗', 'delta': 300},
    ];

    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择字体粗细'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: RadioGroup<int>(
          groupValue: themeState.customFontWeightDelta,
          onChanged: (val) {
            if (val != null) {
              HapticFeedbackUtil.light();
              ref.read(themeProvider.notifier).setUseCustomFontWeight(true);
              ref.read(themeProvider.notifier).setCustomFontWeightDelta(val);
              Navigator.pop(ctx);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final label = opt['label'] as String;
              final delta = opt['delta'] as int;
              final isSelected = themeState.customFontWeightDelta == delta;

              return RadioListTile<int>(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                title: Text(
                  label,
                  style: TextStyle(
                    fontWeight: context.adjustWeight(
                        isSelected ? FontWeight.bold : FontWeight.w600),
                    color: isSelected ? colorScheme.primary : null,
                  ),
                ),
                value: delta,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    Widget section(String title, Widget content) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ),
            AppSectionCard(margin: EdgeInsets.zero, child: content),
          ],
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('个性化'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.paddingOf(context).bottom + 24),
        children: [
          section(
              '明暗模式',
              Column(
                children: [
                  RadioGroup<ThemeMode>(
                    groupValue: themeState.themeMode,
                    onChanged: (val) {
                      if (val == null) return;
                      HapticFeedbackUtil.light();
                      ref.read(themeProvider.notifier).setThemeMode(val);
                    },
                    child: const Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.system,
                          title: Text('跟随系统'),
                        ),
                        Divider(height: 1),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.light,
                          title: Text('浅色模式'),
                        ),
                        Divider(height: 1),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.dark,
                          title: Text('深色模式'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.contrast_rounded, size: 24),
                    title: const Text('纯黑深色模式 (OLED 省电)'),
                    value: themeState.isPureBlackDark,
                    onChanged: (val) {
                      HapticFeedbackUtil.light();
                      ref.read(themeProvider.notifier).setPureBlackDark(val);
                    },
                  ),
                ],
              )),
          const SizedBox(height: 32),
          section(
              '色彩方案',
              Column(
                children: [
                  SwitchListTile(
                    secondary:
                        const Icon(Icons.auto_awesome_outlined, size: 24),
                    title: const Text('Material You (Monet) 动态取色'),
                    value: themeState.useDynamicColor,
                    onChanged: (val) {
                      HapticFeedbackUtil.light();
                      ref.read(themeProvider.notifier).setUseDynamicColor(val);
                    },
                  ),
                  if (!themeState.useDynamicColor) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('预置主题配色搭配',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children:
                            List.generate(AppTheme.themeColors.length, (idx) {
                          final item = AppTheme.themeColors[idx];
                          final name = item['name'] as String;
                          final color = item['color'] as Color;
                          final isSelected = themeState.themeColorIndex == idx;

                          return ChoiceChip(
                            avatar: CircleAvatar(
                                backgroundColor: color, radius: 10),
                            label: Text(name),
                            selected: isSelected,
                            onSelected: (_) {
                              HapticFeedbackUtil.light();
                              ref
                                  .read(themeProvider.notifier)
                                  .setThemeColorIndex(idx);
                            },
                          );
                        }),
                      ),
                    ),
                  ],
                ],
              )),
          const SizedBox(height: 32),
          section(
              '字体粗细',
              Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.format_bold_rounded, size: 24),
                    title: const Text('自定义应用字体粗细'),
                    subtitle: Text(
                        '当前：${_getFontWeightLabel(themeState.customFontWeightDelta)}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () =>
                        _showFontWeightDialog(context, ref, themeState),
                  ),
                ],
              )),
          const SizedBox(height: 32),
          section(
              '导航布局风格',
              SwitchListTile(
                secondary: const Icon(Icons.dock_rounded, size: 24),
                title: const Text('悬浮胶囊底栏 (MD3 Expressive)'),
                value: themeState.useFloatingNavBar,
                onChanged: (val) {
                  HapticFeedbackUtil.light();
                  ref.read(themeProvider.notifier).setUseFloatingNavBar(val);
                },
              )),
          const SizedBox(height: 32),
          section(
              '屏幕显示',
              ListTile(
                leading: const Icon(Icons.speed_rounded, size: 24),
                title: const Text('屏幕帧率设置'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  HapticFeedbackUtil.light();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DisplaySettingsPage(),
                    ),
                  );
                },
              )),
          const SizedBox(height: 32),
          section(
              '触感与震动',
              SwitchListTile(
                secondary: const Icon(Icons.vibration_rounded, size: 24),
                title: const Text('触感与震动反馈'),
                value: themeState.enableHaptics,
                onChanged: (val) {
                  ref.read(themeProvider.notifier).setEnableHaptics(val);
                },
              )),
        ],
      ),
    );
  }

  static String _getFontWeightLabel(int delta) {
    switch (delta) {
      case -100:
        return '偏细';
      case 100:
        return '中等';
      case 200:
        return '偏粗';
      case 300:
        return '加粗';
      case 0:
      default:
        return '默认';
    }
  }
}
