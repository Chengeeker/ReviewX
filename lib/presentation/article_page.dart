import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/storage/reading_settings.dart';
import '../core/widgets/cached_network_image.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/models/social_models.dart';
import '../twitter/models/content_models.dart';
import 'media_page.dart';
import 'timeline_page.dart';
import 'discovery_pages.dart';

class ArticlePage extends ConsumerStatefulWidget {
  const ArticlePage({super.key, required this.post});
  final SocialPost post;
  @override
  ConsumerState<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends ConsumerState<ArticlePage> {
  SocialArticle? _article;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final controller = ref.read(appControllerProvider),
        epoch = ref.read(appControllerProvider).epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await controller.adapter.article(widget.post.id);
      if (!mounted || epoch != controller.epoch) return;
      controller.ingest([post]);
      setState(() => _article = post.article);
    } catch (error) {
      controller.report(error);
      if (mounted && epoch == controller.epoch) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = _article, settings = ref.watch(readingProvider);
    var number = 0;
    return Scaffold(
        appBar: AppBar(title: const Text('X 文章'), actions: [
          IconButton(
              tooltip: '在 X 打开原文',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchUrl(Uri.parse(widget.post.url),
                  mode: LaunchMode.externalApplication))
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(onPressed: _fetch, child: const Text('重试'))
                  ]))
                : article == null
                    ? const Center(child: Text('文章暂不可用'))
                    : ListView(padding: const EdgeInsets.all(20), children: [
                        Text(article.title,
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 12),
                        Text(
                            '${widget.post.author.name} · @${widget.post.author.handle}'),
                        const SizedBox(height: 16),
                        if (article.cover != null)
                          ArticleMedia(
                              media: [article.cover!],
                              author: widget.post.author.handle),
                        if (!article.full) ...[
                          const Text('X 本次只返回文章摘要，完整内容请打开原文。'),
                          const SizedBox(height: 12),
                          SelectableText(article.preview),
                          TextButton(
                              onPressed: () => launchUrl(
                                  Uri.parse(widget.post.url),
                                  mode: LaunchMode.externalApplication),
                              child: const Text('在 X 阅读完整文章')),
                        ] else
                          for (final block in article.blocks)
                            Builder(builder: (context) {
                              if (block.type == 'ordered-list-item') {
                                number++;
                              } else {
                                number = 0;
                              }
                              if (block.type == 'atomic') {
                                return block.media.isEmpty
                                    ? TextButton(
                                        onPressed: () => launchUrl(
                                            Uri.parse(widget.post.url),
                                            mode:
                                                LaunchMode.externalApplication),
                                        child: const Text('此嵌入内容请在 X 查看'))
                                    : Column(children: [
                                        ArticleMedia(
                                            media: block.media,
                                            author: widget.post.author.handle),
                                        if (block.caption.isNotEmpty)
                                          Text(block.caption)
                                      ]);
                              }
                              final heading = const [
                                'header-one',
                                'header-two',
                                'header-three',
                                'header-four',
                                'header-five',
                                'header-six'
                              ].indexOf(block.type);
                              final style = TextStyle(
                                  fontSize: heading >= 0
                                      ? (28 - heading * 2).toDouble()
                                      : settings['fontSize'],
                                  height: settings['lineHeight'],
                                  fontWeight:
                                      heading >= 0 ? FontWeight.bold : null,
                                  fontStyle: block.type == 'blockquote'
                                      ? FontStyle.italic
                                      : null);
                              return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (block.type == 'unordered-list-item')
                                          const Text('•  '),
                                        if (block.type == 'ordered-list-item')
                                          Text('$number.  '),
                                        if (block.type == 'blockquote')
                                          Container(
                                              width: 3,
                                              height: 24,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              margin: const EdgeInsets.only(
                                                  right: 12)),
                                        Expanded(
                                            child: RichContentText(
                                                text: block.text,
                                                style: style,
                                                styles: block.styles,
                                                links: block.links,
                                                selectable: true)),
                                      ]));
                            }),
                      ]));
  }
}

class ArticleMedia extends StatelessWidget {
  const ArticleMedia({super.key, required this.media, required this.author});
  final List<SocialMedia> media;
  final String author;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < media.length; i++)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: GestureDetector(
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MediaPage(
                                media: media, index: i, author: author)));
                  },
                  child: Stack(alignment: Alignment.center, children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(media[i].preview,
                            width: double.infinity, fit: BoxFit.contain)),
                    if (media[i].video != null)
                      const Icon(Icons.play_circle,
                          color: Colors.white, size: 48)
                  ])))
      ]);
}

/// UTF-16 offsets match X/Draft.js ranges; malformed ranges are ignored.
class RichContentText extends ConsumerStatefulWidget {
  const RichContentText(
      {super.key,
      required this.text,
      required this.style,
      this.styles = const [],
      this.links = const [],
      this.selectable = false,
      this.maxLines});
  final String text;
  final TextStyle style;
  final List<Map<String, dynamic>> styles, links;
  final bool selectable;
  final int? maxLines;
  @override
  ConsumerState<RichContentText> createState() => _RichContentTextState();
}

class _RichContentTextState extends ConsumerState<RichContentText> {
  final List<TapGestureRecognizer> _recognizers = [];
  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  Future<void> _open(String target) async {
    if (target.startsWith('@')) {
      final controller = ref.read(appControllerProvider),
          epoch = ref.read(appControllerProvider).epoch;
      try {
        final user = await controller.adapter.userByHandle(target.substring(1));
        if (mounted && epoch == controller.epoch) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => ProfilePage(user: user)));
        }
      } catch (error) {
        controller.report(error);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    } else if (target.startsWith('#') || target.startsWith(r'$')) {
      if (mounted) {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(target)),
                    body: SearchPage(initialQuery: target))));
      }
    } else if (safeLink(target)) {
      await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final links = [...widget.links];
    if (links.isEmpty) {
      for (final match in RegExp(
              r'https?://[^\s<>]+|@[A-Za-z0-9_]{1,15}|#[^\s#]+|\$[A-Za-z]{1,12}')
          .allMatches(widget.text)) {
        links.add({
          'offset': match.start,
          'length': match.end - match.start,
          'url': match[0]
        });
      }
    }
    bool valid(Map<String, dynamic> range) =>
        count(range['offset']) >= 0 &&
        count(range['length']) > 0 &&
        count(range['offset']) + count(range['length']) <= widget.text.length;
    final ranges = [...widget.styles.where(valid), ...links.where(valid)];
    final boundaries = <int>{0, widget.text.length};
    for (final range in ranges) {
      boundaries.add(count(range['offset']));
      boundaries.add(count(range['offset']) + count(range['length']));
    }
    final points = boundaries.toList()..sort(), spans = <TextSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i], end = points[i + 1];
      var style = widget.style;
      bool contains(Map<String, dynamic> range) =>
          valid(range) &&
          count(range['offset']) <= start &&
          count(range['offset']) + count(range['length']) >= end;
      for (final range in widget.styles.where(contains)) {
        switch (range['style']) {
          case 'BOLD':
            style = style.copyWith(fontWeight: FontWeight.bold);
          case 'ITALIC':
            style = style.copyWith(fontStyle: FontStyle.italic);
          case 'UNDERLINE':
            style = style.copyWith(decoration: TextDecoration.underline);
          case 'STRIKETHROUGH':
            style = style.copyWith(decoration: TextDecoration.lineThrough);
          case 'CODE':
            style = style.copyWith(
                fontFamily: 'monospace',
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest);
        }
      }
      final link = links.where(contains).firstOrNull;
      TapGestureRecognizer? recognizer;
      if (link != null) {
        if (ref.watch(readingProvider)['coloredLinks'] == true) {
          style = style.copyWith(color: Theme.of(context).colorScheme.primary);
        }
        recognizer = TapGestureRecognizer()
          ..onTap = () {
            HapticFeedbackUtil.light();
            _open('${link['url']}');
          };
        _recognizers.add(recognizer);
      }
      spans.add(TextSpan(
          text: widget.text.substring(start, end),
          style: style,
          recognizer: recognizer));
    }
    final text = TextSpan(style: widget.style, children: spans);
    return widget.selectable
        ? SelectableText.rich(text)
        : Text.rich(text,
            maxLines: widget.maxLines,
            overflow: widget.maxLines == null
                ? TextOverflow.clip
                : TextOverflow.ellipsis);
  }
}
