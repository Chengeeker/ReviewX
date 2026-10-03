import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/widgets/cached_network_image.dart';
import '../core/storage/reading_settings.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/models/social_models.dart';
import '../twitter/models/content_models.dart';
import 'media_page.dart';
import 'timeline_page.dart';
import 'article_page.dart';
import 'compose_page.dart';

class PostCard extends ConsumerWidget {
  const PostCard(
      {super.key,
      required this.post,
      this.detail = false,
      this.quoted = false});
  final SocialPost post;
  final bool detail, quoted;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final current = controller.effective(post);
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(readingProvider);
    return Container(
        decoration: BoxDecoration(
          color: settings['cardBackground'] == true
              ? scheme.surfaceContainerLowest
              : null,
          border: quoted
              ? Border.all(color: scheme.outlineVariant)
              : Border(bottom: BorderSide(color: scheme.outlineVariant)),
          borderRadius: quoted ? BorderRadius.circular(16) : null,
        ),
        child: InkWell(
            borderRadius: quoted ? BorderRadius.circular(16) : null,
            onTap: detail
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PostDetailPage(post: current))),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (current.repostedBy != null)
                        Padding(
                            padding: const EdgeInsets.only(left: 50, bottom: 8),
                            child: Text('↻ ${current.repostedBy} 转发了',
                                style:
                                    Theme.of(context).textTheme.labelMedium)),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          ProfilePage(user: current.author))),
                              child: ClipOval(
                                  child: current.author.avatar.isEmpty
                                      ? const SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: Icon(Icons.person))
                                      : CachedNetworkImage(
                                          current.author.avatar,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            InkWell(
                                              onTap: () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (_) =>
                                                          ProfilePage(
                                                              user: current
                                                                  .author))),
                                              child: Text(
                                                '${current.author.name}${current.author.verified ? ' ✓' : ''}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall,
                                              ),
                                            ),
                                            Row(children: [
                                              Flexible(
                                                child: InkWell(
                                                  onTap: () => Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (_) =>
                                                              ProfilePage(
                                                                  user: current
                                                                      .author))),
                                                  child: Text(
                                                    '@${current.author.handle}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                                ),
                                              ),
                                              if (current.createdAt != null)
                                                Flexible(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            left: 6),
                                                    child: Text(
                                                      '· ${postTime(current.createdAt!, settings)}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall,
                                                    ),
                                                  ),
                                                ),
                                            ]),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: PopupMenuButton<String>(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                                minWidth: 40, minHeight: 40),
                                            onSelected: (action) async {
                                              if (action == 'copy') {
                                                await Clipboard.setData(
                                                    ClipboardData(
                                                        text: current.text));
                                              }
                                              if (action == 'link') {
                                                await Clipboard.setData(
                                                    ClipboardData(
                                                        text: current.url));
                                              }
                                              if (action == 'open') {
                                                await launchUrl(
                                                    Uri.parse(current.url),
                                                    mode: LaunchMode
                                                        .externalApplication);
                                              }
                                              if (action == 'reply' ||
                                                  action == 'quote') {
                                                if (context.mounted) {
                                                  Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (_) => ComposePage(
                                                              reply: action ==
                                                                      'reply'
                                                                  ? current
                                                                  : null,
                                                              quote: action ==
                                                                      'quote'
                                                                  ? current
                                                                  : null)));
                                                }
                                              }
                                              if (action == 'bookmark') {
                                                try {
                                                  await controller
                                                      .bookmark(current);
                                                } catch (error) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(SnackBar(
                                                            content: Text(
                                                                '$error')));
                                                  }
                                                }
                                              }
                                            },
                                            itemBuilder: (_) => [
                                                  const PopupMenuItem(
                                                      value: 'copy',
                                                      child: Text('复制正文')),
                                                  const PopupMenuItem(
                                                      value: 'link',
                                                      child: Text('复制链接')),
                                                  const PopupMenuItem(
                                                      value: 'open',
                                                      child: Text('在浏览器打开')),
                                                  const PopupMenuItem(
                                                      value: 'reply',
                                                      child: Text('回复')),
                                                  const PopupMenuItem(
                                                      value: 'quote',
                                                      child: Text('引用')),
                                                  PopupMenuItem(
                                                      value: 'bookmark',
                                                      enabled: !controller
                                                          .actionBlocked(
                                                              current.id),
                                                      child: Text(
                                                          current.bookmarked
                                                              ? '移除 X 书签'
                                                              : '保存到 X 书签')),
                                                ]),
                                      ),
                                    ],
                                  ),
                                  if (current.text.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(
                                            top: 8, bottom: 8),
                                        child: _GrokTranslationText(
                                            key: ValueKey(current.id),
                                            original: current.text,
                                            translated: current.translatedText,
                                            autoTranslate:
                                                settings['grokAutoTranslate'] ==
                                                    true,
                                            maxLines: detail ? null : 12,
                                            selectable: detail,
                                            style: TextStyle(
                                                fontSize: settings['fontSize'],
                                                height:
                                                    settings['lineHeight']))),
                                  if (current.replyToHandle != null)
                                    Text('回复 @${current.replyToHandle}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  if (settings['showSource'] == true &&
                                      current.source.isNotEmpty)
                                    Text(current.source,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  if (current.article != null)
                                    Card(
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                            onTap: () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (_) => ArticlePage(
                                                        post: current))),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (current.article!.cover !=
                                                      null)
                                                    CachedNetworkImage(
                                                        current.article!.cover!
                                                            .preview,
                                                        width: double.infinity,
                                                        height: 180,
                                                        fit: BoxFit.cover),
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                                current.article!
                                                                    .title,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .titleMedium),
                                                            if (current
                                                                .article!
                                                                .preview
                                                                .isNotEmpty)
                                                              Text(
                                                                  current
                                                                      .article!
                                                                      .preview,
                                                                  maxLines: 3,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis),
                                                            const Text(
                                                                '阅读 X 文章 →'),
                                                          ]))
                                                ]))),
                                  if (current.linkCard != null &&
                                      current.article == null)
                                    Card(
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                            onTap: () => launchUrl(
                                                Uri.parse(
                                                    current.linkCard!.url),
                                                mode: LaunchMode
                                                    .externalApplication),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (current.linkCard!.image
                                                      .isNotEmpty)
                                                    CachedNetworkImage(
                                                        current.linkCard!.image,
                                                        width: double.infinity,
                                                        height: 150,
                                                        fit: BoxFit.cover),
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                                current
                                                                    .linkCard!
                                                                    .title,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .titleSmall),
                                                            Text(
                                                                current
                                                                    .linkCard!
                                                                    .description,
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis),
                                                            Text(Uri.parse(current
                                                                    .linkCard!
                                                                    .url)
                                                                .host),
                                                          ]))
                                                ]))),
                                  if (current.poll != null)
                                    PollView(
                                        poll: current.poll!, url: current.url),
                                  if (current.media.isNotEmpty)
                                    MediaGrid(post: current),
                                  if (current.quote != null && !quoted)
                                    PostCard(
                                        post: current.quote!, quoted: true),
                                  if (!quoted)
                                    Wrap(
                                        alignment: WrapAlignment.spaceAround,
                                        children: [
                                          TextButton.icon(
                                              onPressed: detail
                                                  ? null
                                                  : () => Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (_) =>
                                                              PostDetailPage(
                                                                  post:
                                                                      current))),
                                              icon: const Icon(
                                                  Icons.chat_bubble_outline,
                                                  size: 19),
                                              label:
                                                  Text('${current.replies}')),
                                          TextButton.icon(
                                              onPressed: controller
                                                      .actionBlocked(current.id)
                                                  ? null
                                                  : () => _action(
                                                      context,
                                                      controller,
                                                      current,
                                                      false),
                                              icon: Icon(Icons.repeat,
                                                  size: 19,
                                                  color: current.reposted
                                                      ? scheme.primary
                                                      : null),
                                              label:
                                                  Text('${current.reposts}')),
                                          TextButton.icon(
                                              onPressed: controller
                                                      .actionBlocked(current.id)
                                                  ? null
                                                  : () => _action(
                                                      context,
                                                      controller,
                                                      current,
                                                      true),
                                              icon: Icon(
                                                  current.liked
                                                      ? Icons.favorite
                                                      : Icons.favorite_border,
                                                  size: 19,
                                                  color: current.liked
                                                      ? scheme.error
                                                      : null),
                                              label: Text('${current.likes}'))
                                        ]),
                                  if (!quoted && current.views > 0)
                                    Text('${current.views} 次浏览',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  if (controller.isUncertain(current.id))
                                    const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text('操作结果待核对，请刷新后再操作'))
                                ])),
                          ])
                    ]))));
  }

  Future<void> _action(BuildContext context, AppController controller,
      SocialPost post, bool like) async {
    try {
      await controller.act(post, like: like);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _GrokTranslationText extends StatefulWidget {
  const _GrokTranslationText({
    super.key,
    required this.original,
    required this.translated,
    required this.autoTranslate,
    required this.maxLines,
    required this.selectable,
    required this.style,
  });

  final String original;
  final String translated;
  final bool autoTranslate;
  final int? maxLines;
  final bool selectable;
  final TextStyle style;

  @override
  State<_GrokTranslationText> createState() => _GrokTranslationTextState();
}

class _GrokTranslationTextState extends State<_GrokTranslationText> {
  bool? _showTranslationOverride;

  @override
  void didUpdateWidget(covariant _GrokTranslationText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoTranslate != widget.autoTranslate ||
        oldWidget.original != widget.original ||
        oldWidget.translated != widget.translated) {
      _showTranslationOverride = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.translated.isEmpty) {
      return RichContentText(
          text: widget.original,
          maxLines: widget.maxLines,
          selectable: widget.selectable,
          style: widget.style);
    }

    final showTranslation = _showTranslationOverride ?? widget.autoTranslate;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RichContentText(
          text: showTranslation ? widget.translated : widget.original,
          maxLines: widget.maxLines,
          selectable: widget.selectable,
          style: widget.style),
      TextButton.icon(
          style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 4)),
          onPressed: () =>
              setState(() => _showTranslationOverride = !showTranslation),
          icon: const Icon(Icons.translate, size: 18),
          label: Text(showTranslation ? '显示原文' : 'Grok 翻译')),
    ]);
  }
}

String postTime(DateTime value, Map<String, dynamic> settings) {
  final date = settings['utcTime'] == true ? value.toUtc() : value.toLocal();
  if (settings['relativeTime'] == true) {
    final delta = DateTime.now().difference(value);
    if (!delta.isNegative && delta.inDays == 0) {
      if (delta.inMinutes == 0) return '刚刚';
      if (delta.inHours == 0) return '${delta.inMinutes} 分钟前';
      return '${delta.inHours} 小时前';
    }
  }
  final pattern =
      '${settings['showYear'] == true ? 'yyyy-' : ''}MM-dd${settings['showWeekday'] == true ? ' E' : ''} HH:mm${settings['showSeconds'] == true ? ':ss' : ''}';
  return '${DateFormat(pattern).format(date)}${settings['utcTime'] == true ? ' UTC' : ''}';
}

class MediaGrid extends ConsumerStatefulWidget {
  const MediaGrid({super.key, required this.post});
  final SocialPost post;
  @override
  ConsumerState<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends ConsumerState<MediaGrid> {
  bool _revealed = false;
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readingProvider), media = widget.post.media;
    if (widget.post.sensitive &&
        !_revealed &&
        settings['showSensitive'] != true) {
      return OutlinedButton.icon(
          onPressed: () => setState(() => _revealed = true),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('显示 X 标记为敏感的媒体'));
    }
    final single = media.length == 1, first = media.first;
    final ratio = single &&
            settings['largeImages'] == true &&
            first.width > 0 &&
            first.height > 0
        ? (first.width / first.height).clamp(0.2, 3.0)
        : single
            ? 1.4
            : 1.0;
    return LayoutBuilder(builder: (context, constraints) {
      final mediaMaxHeight =
          (MediaQuery.sizeOf(context).height * 0.42).clamp(0.0, 480.0);
      final width = single
          ? (mediaMaxHeight * ratio).clamp(0.0, constraints.maxWidth)
          : constraints.maxWidth;
      return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
              width: width,
              child: GridView.builder(
                  padding: EdgeInsets.zero,
                  primary: false,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: media.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: single ? 1 : 2,
                      childAspectRatio: ratio,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6),
                  itemBuilder: (context, index) => GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => MediaPage(
                                  media: media,
                                  index: index,
                                  post: widget.post,
                                  author: widget.post.author.handle))),
                      child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(settings['imageRadius']),
                          child: Stack(fit: StackFit.expand, children: [
                            CachedNetworkImage(media[index].preview,
                                fit: BoxFit.cover),
                            if (media[index].video != null)
                              const Center(
                                  child: Icon(Icons.play_circle_fill,
                                      color: Colors.white, size: 48)),
                            if (media[index].alt.isNotEmpty)
                              const Positioned(
                                  left: 8,
                                  bottom: 8,
                                  child: DecoratedBox(
                                      decoration:
                                          BoxDecoration(color: Colors.black54),
                                      child: Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Text('ALT',
                                              style: TextStyle(
                                                  color: Colors.white))))),
                          ]))))));
    });
  }
}

class PollView extends StatelessWidget {
  const PollView({super.key, required this.poll, required this.url});
  final SocialPoll poll;
  final String url;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < poll.choices.length; i++)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${poll.choices[i]}${poll.selected == i + 1 ? ' ✓' : ''} · ${poll.votes[i]} 票${poll.total == 0 ? '' : ' · ${(poll.votes[i] * 100 / poll.total).toStringAsFixed(1)}%'}'),
                    LinearProgressIndicator(
                        value:
                            poll.total == 0 ? 0 : poll.votes[i] / poll.total),
                  ])),
        Text(
            '${poll.total} 票${poll.endsAt == null ? '' : DateTime.now().isAfter(poll.endsAt!) ? ' · 已结束' : ' · 截止 ${poll.endsAt!.toLocal()}'}'),
        if (poll.endsAt == null || DateTime.now().isBefore(poll.endsAt!))
          TextButton(
              onPressed: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
              child: const Text('在 X 投票')),
      ]));
}
