import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/cache_service.dart';
import '../core/storage/storage_service.dart';
import '../core/utils/app_dialog.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/widgets/app_section_card.dart';
import '../core/widgets/frosted_app_bar.dart';

class CacheManagementPage extends ConsumerStatefulWidget {
  const CacheManagementPage({super.key});

  @override
  ConsumerState<CacheManagementPage> createState() =>
      _CacheManagementPageState();
}

class _CacheManagementPageState extends ConsumerState<CacheManagementPage> {
  CacheBreakdown _stats = CacheBreakdown.empty;
  bool _loading = true;
  bool _clearing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await CacheService.getCacheStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      if (mounted) setState(() => _error = '缓存信息读取失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearCache() async {
    if (_clearing || _loading || _error != null) return;
    HapticFeedbackUtil.light();
    if (_stats.totalBytes == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可清理的缓存')),
      );
      return;
    }

    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理所有缓存？'),
        content: Text(
          '将清理应用缓存目录中的临时文件，共 ${CacheBreakdown.formatBytes(_stats.totalBytes)}。账号、设置和本地时间线快照不会被清理。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      HapticFeedbackUtil.medium();
      final bytes = await CacheService.clearCache();
      await _loadStats();
      if (mounted) {
        HapticFeedbackUtil.medium();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('缓存清理完成，释放 ${CacheBreakdown.formatBytes(bytes)}'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缓存清理失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final threshold = ref.watch(storageServiceProvider).getInt(
        CacheService.thresholdKey,
        defaultValue: CacheService.defaultThresholdMb);
    final insets = MediaQuery.paddingOf(context);
    final appBar = buildFrostedAppBar(
      context,
      title: const Text('缓存管理'),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          insets.top + appBar.preferredSize.height + 12,
          16,
          insets.bottom + 32,
        ),
        children: [
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cleaning_services_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Text(
                      _error ?? CacheBreakdown.formatBytes(_stats.totalBytes),
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _error == null
                                    ? colorScheme.onSurface
                                    : colorScheme.error,
                              ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '可管理的应用缓存',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '图片与媒体、网络临时文件及系统运行时缓存',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  if (!_loading && _error == null) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    _CacheRow(label: '图片与媒体', bytes: _stats.imageBytes),
                    _CacheRow(label: '网络与临时文件', bytes: _stats.networkBytes),
                    _CacheRow(label: '系统运行时', bytes: _stats.systemBytes),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: (_loading || _clearing || _error != null)
                    ? null
                    : _clearCache,
                icon: _clearing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_sweep_rounded),
                label: Text(_clearing ? '正在清理...' : '清理所有缓存'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '自动清理规则',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            child: ListTile(
              leading: Icon(
                Icons.auto_delete_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              title: const Text('自动清理缓存阈值'),
              subtitle: const Text('达到阈值时在启动阶段自动清理；更改后也会立即检查一次'),
              trailing: Text(
                _formatThreshold(threshold),
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: _clearing || _loading ? null : _showThresholdSelector,
            ),
          ),
          const SizedBox(height: 24),
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '清理仅针对 Android 应用缓存目录，并清空 Flutter 图片内存缓存；账号凭据、设置、本地时间线快照和已保存到相册的媒体不会受影响。缓存分类按文件路径估算；正在播放或保存的临时媒体可能需要重新加载。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: _loading || _clearing ? null : _loadStats,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新缓存占用'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showThresholdSelector() async {
    HapticFeedbackUtil.light();
    final selected = await showAppDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择自动清理阈值'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: RadioGroup<int>(
          groupValue: ref.read(storageServiceProvider).getInt(
              CacheService.thresholdKey,
              defaultValue: CacheService.defaultThresholdMb),
          onChanged: (value) => Navigator.pop(context, value),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: CacheService.thresholdsMb
                  .map((value) => RadioListTile<int>(
                        title: Text(_formatThreshold(value)),
                        value: value,
                        dense: true,
                      ))
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    HapticFeedbackUtil.selection();
    await ref
        .read(storageServiceProvider)
        .setInt(CacheService.thresholdKey, selected);
    if (!mounted) return;
    setState(() {});
    try {
      if (await CacheService.checkAndAutoClearCache(selected)) {
        await _loadStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('缓存达到新阈值，已自动清理')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存阈值，但自动清理失败')),
        );
      }
    }
  }

  String _formatThreshold(int mb) {
    if (mb == 0) return '不限制总缓存占用';
    if (mb >= 1024) return '${mb ~/ 1024} GB';
    return '$mb MB';
  }
}

class _CacheRow extends StatelessWidget {
  const _CacheRow({required this.label, required this.bytes});

  final String label;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textStyle)),
          Text(
            CacheBreakdown.formatBytes(bytes),
            style: textStyle?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
