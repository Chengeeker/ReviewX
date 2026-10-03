import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/media_saver.dart';
import '../core/storage/reading_settings.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/models/social_models.dart';

class MediaPage extends ConsumerStatefulWidget {
  const MediaPage(
      {super.key, required this.media, required this.index, this.author = ''});
  final List<SocialMedia> media;
  final int index;
  final String author;
  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage> {
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _index = widget.index;
  bool _saving = false;
  Future<void> _save() async {
    if (_saving) return;
    final media = widget.media[_index],
        mode = ref.read(readingProvider)['storageFolder'];
    final folder = mode == 'author'
        ? widget.author
        : mode == 'me'
            ? ref.read(appControllerProvider).me?.handle ??
                ref.read(appControllerProvider).client.session?.userId ??
                ''
            : '';
    setState(() => _saving = true);
    try {
      await MediaSaver.save(media, folder);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存到系统相册')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_index + 1}/${widget.media.length}'),
          actions: [
            if (widget.media[_index].alt.isNotEmpty)
              IconButton(
                  tooltip: '图片说明',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                              title: const Text('图片说明'),
                              content: SelectableText(widget.media[_index].alt),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('关闭'))
                              ]))),
            IconButton(
                tooltip: '保存到相册',
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download)),
          ]),
      body: PageView.builder(
          controller: _pages,
          itemCount: widget.media.length,
          onPageChanged: (index) => setState(() => _index = index),
          itemBuilder: (context, index) {
            final media = widget.media[index];
            if (media.video != null) {
              return VideoPane(
                  key: ValueKey(media.video),
                  url: media.video!,
                  active: _index == index);
            }
            return ExtendedImage.network(media.original,
                cache: true,
                fit: BoxFit.contain,
                mode: ExtendedImageMode.gesture,
                onDoubleTap: (state) {
                  final scale = state.gestureDetails?.totalScale ?? 1;
                  state.handleDoubleTap(
                      scale: scale > 1 ? 1 : 2.5,
                      doubleTapPosition: state.pointerDownPosition);
                },
                initGestureConfigHandler: (_) =>
                    GestureConfig(minScale: 1, maxScale: 5, inPageView: true));
          }));
}

class VideoPane extends StatefulWidget {
  const VideoPane({super.key, required this.url, required this.active});
  final String url;
  final bool active;
  @override
  State<VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<VideoPane> with WidgetsBindingObserver {
  late final VideoPlayerController _video =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false, _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      if (widget.active) _video.play();
    }).catchError((Object error) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _video.pause();
  }

  @override
  void didUpdateWidget(covariant VideoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _video.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
          child: Text('视频加载失败，请返回后重试', style: TextStyle(color: Colors.white)));
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Center(
        child: Column(children: [
      Expanded(
          child: Center(
              child: AspectRatio(
                  aspectRatio: _video.value.aspectRatio,
                  child: VideoPlayer(_video)))),
      VideoProgressIndicator(_video,
          allowScrubbing: true, padding: const EdgeInsets.all(16)),
      ValueListenableBuilder(
          valueListenable: _video,
          builder: (context, value, _) => IconButton(
              color: Colors.white,
              onPressed: () => value.isPlaying ? _video.pause() : _video.play(),
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow)))
    ]));
  }
}
