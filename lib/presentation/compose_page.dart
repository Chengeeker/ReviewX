import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/api/twitter_client.dart';
import '../twitter/models/social_models.dart';

class ComposePage extends ConsumerStatefulWidget {
  const ComposePage({super.key, this.reply, this.quote});
  final SocialPost? reply, quote;
  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  final _text = TextEditingController();
  bool _busy = false, _uncertain = false;
  String? _error, _published;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_busy || _uncertain || _published != null) return;
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await controller.adapter.publish(_text.text,
          replyId: widget.reply?.id, quoteUrl: widget.quote?.url);
      if (mounted && epoch == controller.epoch) setState(() => _published = id);
    } catch (error) {
      controller.report(error);
      if (mounted && epoch == controller.epoch) {
        setState(() {
          _error = '$error';
          _uncertain = error is TwitterFailure && error.uncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
          appBar: AppBar(
              title: Text(widget.reply != null
                  ? '回复'
                  : widget.quote != null
                      ? '引用帖子'
                      : '发布帖子'),
              actions: [
                TextButton(
                    onPressed: _busy || _uncertain || _published != null
                        ? null
                        : _publish,
                    child: Text(_busy ? '提交中…' : '发布')),
              ]),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            if (widget.reply != null)
              Text('回复 @${widget.reply!.author.handle}'),
            if (widget.quote != null)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                          '@${widget.quote!.author.handle}\n${widget.quote!.text}',
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis))),
            TextField(
                controller: _text,
                readOnly: _busy || _uncertain || _published != null,
                autofocus: true,
                minLines: 6,
                maxLines: null,
                maxLength: 10000,
                decoration: const InputDecoration(
                    hintText: '有什么新鲜事？',
                    border: OutlineInputBorder(),
                    helperText: '本页发布文字，X 会校验账号对应的长度限制')),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_uncertain) ...[
              const Text('这次发布结果尚未确认。请先在 X 主页核对，避免重复发布。'),
              TextButton(
                  onPressed: () => launchUrl(Uri.parse('https://x.com/home'),
                      mode: LaunchMode.externalApplication),
                  child: const Text('在 X 核对')),
              TextButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _text.text)),
                  child: const Text('复制正文')),
            ],
            if (_published != null) ...[
              const Text('X 已返回发布成功的帖子编号'),
              SelectableText(_published!),
              TextButton(
                  onPressed: () => launchUrl(
                      Uri.parse('https://x.com/i/status/$_published'),
                      mode: LaunchMode.externalApplication),
                  child: const Text('查看已发布帖子')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, _published),
                  child: const Text('完成')),
            ],
          ])));
}
