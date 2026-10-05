import 'dart:async';
import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/media_saver.dart';
import '../core/widgets/cached_network_image.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/storage/reading_settings.dart';
import '../twitter/api/x_request_headers.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/models/social_models.dart';
import 'review_video_player.dart';

// Gallery paging, zoom and dismiss gestures are adapted from Review (MIT);
// Twitter media loading and saving continue to use ReviewX's own models/services.
class MediaPage extends ConsumerStatefulWidget {
  const MediaPage(
      {super.key,
      required this.media,
      required this.index,
      this.author = '',
      this.post});
  final List<SocialMedia> media;
  final int index;
  final String author;
  final SocialPost? post;
  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage>
    with SingleTickerProviderStateMixin {
  late final ExtendedPageController _pages =
      ExtendedPageController(initialPage: widget.index);
  final GlobalKey<ExtendedImageSlidePageState> _slidePageKey =
      GlobalKey<ExtendedImageSlidePageState>();
  late int _index = widget.index;
  bool _saving = false, _showChrome = true;

  late final AnimationController _doubleTapAnimationController =
      AnimationController(
          duration: const Duration(milliseconds: 260), vsync: this);
  Animation<double>? _doubleTapAnimation;
  VoidCallback? _doubleTapListener;
  int _zoomGeneration = 0;

  Future<void> _save() async {
    if (_saving) return;
    final media = widget.media[_index];
    final mode = ref.read(readingProvider)['storageFolder'];
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

  void _stopDoubleTapAnimation() {
    _zoomGeneration++;
    _doubleTapAnimationController.stop();
    final listener = _doubleTapListener;
    if (listener != null) {
      _doubleTapAnimation?.removeListener(listener);
    }
    _doubleTapListener = null;
    _doubleTapAnimation = null;
  }

  void _handleImageDoubleTap(ExtendedImageGestureState state, int pageIndex) {
    HapticFeedbackUtil.light();
    _stopDoubleTapAnimation();
    final generation = _zoomGeneration;
    final pointerDownPosition = state.pointerDownPosition;
    final begin = state.gestureDetails?.totalScale ?? 1.0;
    final end = begin <= 1.05
        ? 2.5
        : begin <= 3.6
            ? 6.0
            : 1.0;

    _doubleTapAnimation = Tween<double>(begin: begin, end: end).animate(
      CurvedAnimation(
          parent: _doubleTapAnimationController, curve: Curves.easeOutCubic),
    );
    _doubleTapListener = () {
      if (!mounted || pageIndex != _index || generation != _zoomGeneration) {
        return;
      }
      state.handleDoubleTap(
          scale: _doubleTapAnimation!.value,
          doubleTapPosition: pointerDownPosition);
    };
    _doubleTapAnimation!.addListener(_doubleTapListener!);
    _doubleTapAnimationController.forward(from: 0);
  }

  void _onPageChanged(int index) {
    _stopDoubleTapAnimation();
    if (mounted) setState(() => _index = index);
  }

  void _toggleChrome() {
    if (!mounted) return;
    final showChrome = !_showChrome;
    setState(() => _showChrome = showChrome);
    unawaited(SystemChrome.setEnabledSystemUIMode(
        showChrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky));
  }

  void _handleGalleryTap(TapUpDetails details) {
    HapticFeedbackUtil.light();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final x = details.globalPosition.dx;
    final isMiddleThird = x >= screenWidth / 3 && x < screenWidth * 2 / 3;
    if (isMiddleThird) {
      _toggleChrome();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.media.length || index == _index) return;
    _pages.animateToPage(index,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _stopDoubleTapAnimation();
    _doubleTapAnimationController.dispose();
    _pages.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Widget _buildChrome(SocialMedia media) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AnimatedSlide(
          offset: _showChrome ? Offset.zero : const Offset(0, -1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _showChrome ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: !_showChrome,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black45),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        tooltip: '返回',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${_index + 1} / ${widget.media.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (media.alt.isNotEmpty)
                          IconButton(
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.black45),
                            icon: const Icon(Icons.info_outline,
                                color: Colors.white),
                            tooltip: '图片说明',
                            onPressed: () => showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                      title: const Text('图片说明'),
                                      content: SelectableText(media.alt),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('关闭'))
                                      ],
                                    )),
                          ),
                        IconButton(
                          style: IconButton.styleFrom(
                              backgroundColor: Colors.black45),
                          tooltip: '保存到相册',
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.download_rounded,
                                  color: Colors.white),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final currentMedia = widget.media[_index];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ExtendedImageSlidePage(
        key: _slidePageKey,
        slideAxis: SlideAxis.horizontal,
        slideType: SlideType.onlyImage,
        slidePageBackgroundHandler: (offset, pageSize) {
          final alpha = (1 - offset.dx.abs() / math.max(1, pageSize.width / 2))
              .clamp(0.0, 1.0)
              .toDouble();
          return Colors.black.withValues(alpha: alpha);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTapUp: currentMedia.video == null ? _handleGalleryTap : null,
                child: ExtendedImageGesturePageView.builder(
                  controller: _pages,
                  physics: currentMedia.video != null
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  itemCount: widget.media.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final media = widget.media[index];
                    if (media.video != null) {
                      return ReviewVideoPlayer(
                        key: ValueKey('$index/${media.video}'),
                        media: media,
                        active: _index == index,
                        post: widget.post,
                        author: widget.author,
                        pageLabel: '${index + 1}/${widget.media.length}',
                        onPrevious: index > 0 ? () => _goTo(index - 1) : null,
                        onNext: index + 1 < widget.media.length
                            ? () => _goTo(index + 1)
                            : null,
                      );
                    }

                    return LayoutBuilder(builder: (context, viewport) {
                      final imageUrl = media.viewerImage(
                        viewportWidth: viewport.maxWidth,
                        viewportHeight: viewport.maxHeight,
                        devicePixelRatio:
                            MediaQuery.devicePixelRatioOf(context),
                      );
                      return SizedBox.expand(
                        child: Stack(fit: StackFit.expand, children: [
                          if (imageUrl != media.preview)
                            CachedNetworkImage(media.preview,
                                fit: BoxFit.contain),
                          ExtendedImage.network(
                            imageUrl,
                            key: ValueKey(imageUrl),
                            width: viewport.maxWidth,
                            height: viewport.maxHeight,
                            headers: XRequestHeaders.media,
                            alignment: Alignment.center,
                            cache: true,
                            fit: BoxFit.contain,
                            mode: ExtendedImageMode.gesture,
                            enableSlideOutPage: false,
                            loadStateChanged: (state) {
                              if (state.extendedImageLoadState ==
                                      LoadState.loading ||
                                  state.extendedImageLoadState ==
                                      LoadState.failed) {
                                // Keep the already cached feed image visible
                                // while a genuinely larger original is fetched.
                                return const SizedBox.expand();
                              }
                              return null;
                            },
                            onDoubleTap: (state) =>
                                _handleImageDoubleTap(state, index),
                            initGestureConfigHandler: (_) => GestureConfig(
                              minScale: 0.8,
                              animationMinScale: 0.6,
                              maxScale: 8,
                              animationMaxScale: 9,
                              speed: 1,
                              inertialSpeed: 120,
                              initialScale: 1,
                              cacheGesture: false,
                              inPageView: true,
                            ),
                          ),
                        ]),
                      );
                    });
                  },
                ),
              ),
              if (currentMedia.video == null) _buildChrome(currentMedia),
            ],
          ),
        ),
      ),
    );
  }
}
