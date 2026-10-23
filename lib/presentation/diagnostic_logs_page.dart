import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/diagnostic_log.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/widgets/app_section_card.dart';
import '../core/widgets/frosted_app_bar.dart';

class DiagnosticLogsPage extends StatefulWidget {
  const DiagnosticLogsPage({super.key});

  @override
  State<DiagnosticLogsPage> createState() => _DiagnosticLogsPageState();
}

class _DiagnosticLogsPageState extends State<DiagnosticLogsPage> {
  static const _shareChannel = MethodChannel('com.review.x/media');
  bool _sharing = false;

  Future<void> _shareLogs() async {
    if (_sharing) return;
    HapticFeedbackUtil.light();
    setState(() => _sharing = true);
    try {
      final text = await DiagnosticLog.exportText();
      await _shareChannel.invokeMethod<void>('shareText', {
        'text': text,
        'title': '分享 ReviewX 诊断日志',
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日志导出失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final insets = MediaQuery.paddingOf(context);
    final appBar = buildFrostedAppBar(
      context,
      title: const Text('诊断日志'),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          insets.top + appBar.preferredSize.height + 16,
          16,
          insets.bottom + 32,
        ),
        children: [
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                children: [
                  Icon(
                    Icons.bug_report_outlined,
                    size: 42,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '导出诊断日志',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '日志保存在本机，最多保留最近 300 条记录。点击下方按钮后，系统会打开分享菜单，由你选择是否发送。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : _shareLogs,
                      icon: _sharing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share_rounded),
                      label: Text(_sharing ? '正在准备日志…' : '生成并分享日志'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined,
                      color: colorScheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '日志包含应用版本、系统版本、崩溃类型与精简调用位置，以及接口操作、状态码和耗时。不会记录 Cookie、账号、帖子内容或接口正文；异常原文也不会导出。',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
