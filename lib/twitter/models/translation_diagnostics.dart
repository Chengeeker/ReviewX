class TranslationLogEntry {
  const TranslationLogEntry({
    required this.postId,
    required this.authorHandle,
    required this.textPreview,
    required this.hasGrokField,
    required this.isAvailable,
    required this.destinationLanguage,
    required this.translationPreview,
    required this.resultStatus,
    required this.detailReason,
    required this.timestamp,
  });

  final String postId;
  final String authorHandle;
  final String textPreview;
  final bool hasGrokField;
  final bool? isAvailable;
  final String destinationLanguage;
  final String translationPreview;
  final String resultStatus;
  final String detailReason;
  final DateTime timestamp;

  String toFormattedReport() {
    final timeStr =
        '${timestamp.year}-${_twoDigits(timestamp.month)}-${_twoDigits(timestamp.day)} '
        '${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}:${_twoDigits(timestamp.second)}';
    return '''
[推文 ID]: $postId
[作者]: @$authorHandle
[记录时间]: $timeStr
[解析状态]: $resultStatus
[原文摘要]: $textPreview
[X API 下发 Grok]: ${hasGrokField ? "是" : "否"}
[is_available 标记]: ${isAvailable == null ? "无" : isAvailable.toString()}
[目标语言 (destination_language)]: ${destinationLanguage.isEmpty ? "空/无" : destinationLanguage}
[译文摘要]: ${translationPreview.isEmpty ? "无" : translationPreview}
[诊断原因与排查提示]: $detailReason
----------------------------------------''';
  }

  static String _twoDigits(int n) => n >= 10 ? '$n' : '0$n';
}

class TranslationDiagnostics {
  static final List<TranslationLogEntry> _logs = [];
  static const int maxLogs = 100;

  static void record(TranslationLogEntry entry) {
    // Replace existing log for same post if newer
    _logs.removeWhere((item) => item.postId == entry.postId);
    if (_logs.length >= maxLogs) {
      _logs.removeAt(0);
    }
    _logs.add(entry);
  }

  static List<TranslationLogEntry> get logs => List.unmodifiable(_logs.reversed);

  static TranslationLogEntry? getForPost(String postId) {
    for (var i = _logs.length - 1; i >= 0; i--) {
      if (_logs[i].postId == postId) return _logs[i];
    }
    return null;
  }

  static void clear() {
    _logs.clear();
  }

  static String exportAll() {
    if (_logs.isEmpty) {
      return '当前暂无翻译解析日志。\n请先在时间线中浏览帖子或刷新时间线。';
    }
    final buffer = StringBuffer();
    buffer.writeln('=== ReviewX 翻译诊断与日志导出报告 ===');
    buffer.writeln('记录总数: ${_logs.length}');
    buffer.writeln('导出时间: ${DateTime.now().toLocal()}');
    buffer.writeln('========================================\n');
    for (final entry in _logs.reversed) {
      buffer.writeln(entry.toFormattedReport());
    }
    return buffer.toString();
  }
}
