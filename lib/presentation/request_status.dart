import 'package:flutter/material.dart';

/// Visible even when cached content fills several screens.
class RequestStatus extends StatelessWidget {
  const RequestStatus(
      {super.key, required this.loading, this.error, required this.onRetry});
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!loading && error == null) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          if (loading)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(loading ? '正在连接 X… 若等待较久，请检查 VPN 或代理' : error!)),
          if (!loading) TextButton(onPressed: onRetry, child: const Text('重试')),
        ]),
      ),
    );
  }
}
