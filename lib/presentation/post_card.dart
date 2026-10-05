import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/widgets/cached_network_image.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/storage/reading_settings.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/models/social_models.dart';
import '../twitter/models/content_models.dart';
import 'media_page.dart';
import 'timeline_page.dart';
import 'article_page.dart';
import 'compose_page.dart';

class _ReplyContext extends StatelessWidget {
  const _ReplyContext(
      {required this.post, this.parent, this.showPreview = true});
  final SocialPost post;
  final SocialPost? parent;
  final bool showPreview;

  @override
  Widget build(BuildContext context) {
    final target = parent?.author.handle ?? post.replyToHandle;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.subdirectory_arrow_right,
              size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
              child: Text(target == null ? '回复帖子' : '回复 @$target',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.primary))),
        ]),
        if (parent != null && showPreview)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PostDetailPage(post: parent!))),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(parent!.author.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium),
                        Text(parent!.text.isEmpty ? '查看原帖' : parent!.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                      ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class PostCard extends ConsumerWidget {
  const PostCard(
      {super.key,
      required this.post,
      this.replyParent,
      this.showReplyParentPreview = true,
      this.connectedAbove = false,
      this.connectedBelow = false,
      this.detail = false,
      this.quoted = false});
  final SocialPost post;
  final SocialPost? replyParent;
  final bool showReplyParentPreview;
  final bool connectedAbove, connectedBelow;
  final bool detail, quoted;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final current = controller.effective(post);
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(readingProvider);
    final connected = !quoted && (connectedAbove || connectedBelow);
    final card = Container(
        decoration: BoxDecoration(
          color: settings['cardBackground'] == true
              ? scheme.surfaceContainerLowest
              : null,
          border: quoted
              ? Border.all(color: scheme.outlineVariant)
              : Border(
                  left: !connected &&
                          (current.replyToId != null ||
                              current.replyToHandle != null)
                      ? BorderSide(
                          color: scheme.primary.withValues(alpha: 0.35),
                          width: 2)
                      : BorderSide.none,
                  bottom: connectedBelow
                      ? BorderSide.none
                      : BorderSide(color: scheme.outlineVariant)),
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
                            padding: const EdgeInsets.only(bottom: 8),
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
                                                              ? '移除书签'
                                                              : '保存到书签')),
                                                ]),
                                      ),
                                    ],
                                  ),
                                ])),
                          ]),
                      const SizedBox(height: 12),
                      if (current.replyToHandle != null ||
                          current.replyToId != null)
                        _ReplyContext(
                            post: current,
                            parent: replyParent,
                            showPreview: showReplyParentPreview),
                      if (current.text.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: _GrokTranslationText(
                                key: ValueKey(current.id),
                                original: current.text,
                                translated: current.translatedText,
                                autoTranslate:
                                    settings['grokAutoTranslate'] == true,
                                maxLines: detail ? null : 12,
                                selectable: detail,
                                style: TextStyle(
                                    fontSize: settings['fontSize'],
                                    height: settings['lineHeight']))),
                      if (settings['showSource'] == true &&
                          current.source.isNotEmpty)
                        Text(current.source,
                            style: Theme.of(context).textTheme.labelSmall),
                      if (current.article != null)
                        Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            ArticlePage(post: current))),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (current.article!.cover != null)
                                        CachedNetworkImage(
                                            current.article!.cover!.preview,
                                            width: double.infinity,
                                            height: 180,
                                            fit: BoxFit.cover),
                                      Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(current.article!.title,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium),
                                                if (current.article!.preview
                                                    .isNotEmpty)
                                                  Text(current.article!.preview,
                                                      maxLines: 3,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                const Text('阅读 X 文章 →'),
                                              ]))
                                    ]))),
                      if (current.linkCard != null && current.article == null)
                        Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                                onTap: () => launchUrl(
                                    Uri.parse(current.linkCard!.url),
                                    mode: LaunchMode.externalApplication),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (current.linkCard!.image.isNotEmpty)
                                        CachedNetworkImage(
                                            current.linkCard!.image,
                                            width: double.infinity,
                                            height: 150,
                                            fit: BoxFit.cover),
                                      Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(current.linkCard!.title,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall),
                                                Text(
                                                    current
                                                        .linkCard!.description,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                                Text(Uri.parse(
                                                        current.linkCard!.url)
                                                    .host),
                                              ]))
                                    ]))),
                      if (current.poll != null)
                        PollView(poll: current.poll!, url: current.url),
                      if (current.media.isNotEmpty) MediaGrid(post: current),
                      if (current.quote != null && !quoted) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Row(children: [
                            const Icon(Icons.format_quote, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    '引用 @${current.quote!.author.handle} 的帖子',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium)),
                          ]),
                        ),
                        PostCard(post: current.quote!, quoted: true),
                      ],
                      if (!quoted)
                        _PostActionRow(post: current, detail: detail),
                      if (controller.isUncertain(current.id))
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('操作结果待核对，请刷新后再操作'))
                    ]))));
    if (!connected) return card;
    return CustomPaint(
      painter: _ConversationConnector(
          above: connectedAbove,
          below: connectedBelow,
          color: scheme.primary.withValues(alpha: 0.5)),
      child: Padding(padding: const EdgeInsets.only(left: 16), child: card),
    );
  }
}

class _PostActionRow extends ConsumerWidget {
  const _PostActionRow({required this.post, required this.detail});
  final SocialPost post;
  final bool detail;

  String _compact(int value) {
    if (value >= 1000000) return _short(value / 1000000, 'M');
    if (value >= 1000) return _short(value / 1000, 'K');
    return '$value';
  }

  String _short(double value, String suffix) =>
      '${value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}$suffix';

  Widget _action({
    required BuildContext context,
    required String label,
    required IconData icon,
    String? count,
    Color? color,
    VoidCallback? onTap,
  }) =>
      Expanded(
          child: Tooltip(
              message: label,
              child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                      height: 40,
                      child: Center(
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon, size: 17, color: color),
                                    if (count != null) ...[
                                      const SizedBox(width: 3),
                                      Text(count,
                                          maxLines: 1,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: color ??
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)),
                                    ]
                                  ])))))));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final blocked = controller.actionBlocked(post.id);

    Future<void> act(bool like) async {
      try {
        await controller.act(post, like: like);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }

    Future<void> bookmark() async {
      try {
        await controller.bookmark(post);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }

    Future<void> share() async {
      try {
        await const MethodChannel('com.review.x/media').invokeMethod<void>(
            'shareText', {'text': post.url, 'title': '分享帖子'});
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: post.url));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('帖子链接已复制')));
        }
      }
    }

    return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(key: const ValueKey('post-action-row'), children: [
          _action(
              context: context,
              label: '回复',
              icon: Icons.chat_bubble_outline,
              count: _compact(post.replies),
              onTap: detail
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => PostDetailPage(post: post)))),
          _action(
              context: context,
              label: post.reposted ? '取消转发' : '转发',
              icon: Icons.repeat,
              count: _compact(post.reposts),
              color: post.reposted ? scheme.primary : null,
              onTap: blocked ? null : () => act(false)),
          _action(
              context: context,
              label: post.liked ? '取消喜欢' : '喜欢',
              icon: post.liked ? Icons.favorite : Icons.favorite_border,
              count: _compact(post.likes),
              color: post.liked ? scheme.error : null,
              onTap: blocked ? null : () => act(true)),
          _action(
              context: context,
              label: '查看次数',
              icon: Icons.bar_chart_rounded,
              count: _compact(post.views)),
          _action(
              context: context,
              label: post.bookmarked ? '移除书签' : '加入书签',
              icon: post.bookmarked
                  ? Icons.bookmark
                  : Icons.bookmark_border_rounded,
              color: post.bookmarked ? scheme.primary : null,
              onTap: blocked ? null : bookmark),
          _action(
              context: context,
              label: '分享',
              icon: Icons.share_outlined,
              onTap: share),
        ]));
  }
}

/// The spine stays in a separate gutter so full-width body text cannot overlap it.
class _ConversationConnector extends CustomPainter {
  const _ConversationConnector(
      {required this.above, required this.below, required this.color});
  final bool above, below;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const centerY = 30.0; // Card top padding (10) + avatar radius (20).
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(8, above ? 0 : centerY),
        Offset(8, below ? size.height : centerY), paint);
    canvas.drawLine(const Offset(8, centerY), const Offset(28, centerY), paint);
  }

  @override
  bool shouldRepaint(_ConversationConnector oldDelegate) =>
      above != oldDelegate.above ||
      below != oldDelegate.below ||
      color != oldDelegate.color;
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
  late final Object _heroScope = Object();
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
                itemBuilder: (context, index) {
                  final item = media[index];
                  final isVideo = item.video != null;
                  final thumbnail = ClipRRect(
                      borderRadius:
                          BorderRadius.circular(settings['imageRadius']),
                      child: Stack(fit: StackFit.expand, children: [
                        CachedNetworkImage(item.preview, fit: BoxFit.cover),
                        if (isVideo)
                          const Center(
                              child: Icon(Icons.play_circle_fill,
                                  color: Colors.white, size: 48)),
                        if (item.alt.isNotEmpty)
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
                      ]));
                  return GestureDetector(
                    key: ValueKey('post-media-${widget.post.id}-$index'),
                    onTap: () {
                      HapticFeedbackUtil.light();
                      final page = MediaPage(
                          media: media,
                          index: index,
                          post: widget.post,
                          author: widget.post.author.handle,
                          heroScope: isVideo ? null : _heroScope,
                          heroThumbnailUsesCover: !isVideo);
                      Navigator.of(context).push<void>(isVideo
                          ? MaterialPageRoute<void>(
                              builder: (_) => page,
                            )
                          : MediaGalleryRoute<void>(child: page));
                    },
                    child: isVideo
                        ? thumbnail
                        : Hero(
                            tag: mediaGalleryHeroTag(
                              _heroScope,
                              index,
                              imageAspectRatio:
                                  mediaGalleryImageAspectRatio(item),
                              thumbnailUsesCover: true,
                            ),
                            flightShuttleBuilder:
                                mediaGalleryHeroFlightShuttleBuilder,
                            child: thumbnail,
                          ),
                  );
                }),
          ));
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
