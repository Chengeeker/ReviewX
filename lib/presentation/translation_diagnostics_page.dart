import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../twitter/models/translation_diagnostics.dart';

class TranslationDiagnosticsPage extends StatefulWidget {
  const TranslationDiagnosticsPage({super.key});

  @override
  State<TranslationDiagnosticsPage> createState() =>
      _TranslationDiagnosticsPageState();
}

class _TranslationDiagnosticsPageState
    extends State<TranslationDiagnosticsPage> {
  void _copyAll() {
    HapticFeedbackUtil.light();
    final report = TranslationDiagnostics.exportAll();
    Clipboard.setData(ClipboardData(text: report));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制全部翻译诊断报告')),
    );
  }

  void _clearLogs() {
    HapticFeedbackUtil.selection();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空翻译日志？'),
        content: const Text('将清空当前内存中记录的推文翻译解析日志。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              setState(() => TranslationDiagnostics.clear());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('翻译日志已清空')),
              );
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  void _showEntryDetail(TranslationLogEntry entry) {
    HapticFeedbackUtil.light();
    final text = entry.toFormattedReport();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('@${entry.authorHandle} 的推文翻译诊断'),
        content: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('该条诊断已复制')),
              );
            },
            child: const Text('复制诊断'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = TranslationDiagnostics.logs;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译日志与排查诊断'),
        actions: [
          IconButton(
            tooltip: '复制全部报告',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: logs.isEmpty ? null : _copyAll,
          ),
          IconButton(
            tooltip: '清空日志',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: logs.isEmpty ? null : _clearLogs,
          ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.translate_outlined,
                        size: 56, color: colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      '暂无推文翻译日志',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '在主页时间线浏览推文或下拉刷新后，解析过程与诊断信息将自动记录于此。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.outline),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = logs[index];
                final isSuccess = entry.resultStatus.contains('成功');
                final isCache = entry.resultStatus.contains('缓存');
                final badgeColor = isSuccess
                    ? Colors.green
                    : (isCache ? Colors.blueGrey : Colors.orange);

                return Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showEntryDetail(entry),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '@${entry.authorHandle}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: badgeColor.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  entry.resultStatus,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.textPreview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (entry.translationPreview.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '译: ${entry.translationPreview}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            entry.detailReason,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
