import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderClipRRect, RenderImage;
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

/// Shared by the tapped thumbnail and the active image in the gallery route.
@immutable
class MediaGalleryHeroTag {
  const MediaGalleryHeroTag({
    required this.scope,
    required this.index,
    required this.imageAspectRatio,
    required this.thumbnailUsesCover,
  });

  final Object scope;
  final int index;
  final double? imageAspectRatio;
  final bool thumbnailUsesCover;

  @override
  bool operator ==(Object other) =>
      other is MediaGalleryHeroTag &&
      identical(scope, other.scope) &&
      index == other.index;

  @override
  int get hashCode => Object.hash(identityHashCode(scope), index);
}

MediaGalleryHeroTag mediaGalleryHeroTag(
  Object scope,
  int index, {
  double? imageAspectRatio,
  bool thumbnailUsesCover = false,
}) =>
    MediaGalleryHeroTag(
      scope: scope,
      index: index,
      imageAspectRatio: imageAspectRatio,
      thumbnailUsesCover: thumbnailUsesCover,
    );

double? mediaGalleryImageAspectRatio(SocialMedia media) {
  if (media.width <= 0 || media.height <= 0) return null;
  final aspectRatio = media.width / media.height;
  return aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : null;
}

/// Uses the full-size gallery child while entering, then gradually changes
/// its contain fit into the source thumbnail's cover crop while returning.
Widget mediaGalleryHeroFlightShuttleBuilder(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final fromHero = fromHeroContext.widget as Hero;
  final toHero = toHeroContext.widget as Hero;
  if (flightDirection != HeroFlightDirection.pop) return toHero.child;

  final tag = fromHero.tag;
  final targetRenderObject = toHeroContext.findRenderObject();
  if (tag is! MediaGalleryHeroTag ||
      !tag.thumbnailUsesCover ||
      targetRenderObject is! RenderBox ||
      !targetRenderObject.hasSize ||
      targetRenderObject.size.width <= 0 ||
      targetRenderObject.size.height <= 0) {
    return fromHero.child;
  }

  final source = _HeroImageGeometry.capture(fromHeroContext);
  final target = _HeroImageGeometry.capture(toHeroContext);
  if (source == null || target == null) return fromHero.child;
  return _HeroReturnImageMorph(
    animation: animation,
    image: source.image.clone(),
    source: source,
    target: target,
  );
}

/// Captures the complete image plane and its crop relative to its Hero.
/// ExtendedImage uses its own RenderBox, separate from Flutter's RenderImage.
class _HeroImageGeometry {
  const _HeroImageGeometry(this.image, this.rect, this.radius);

  final ui.Image image;
  final Rect rect;
  final BorderRadius radius;

  static _HeroImageGeometry? capture(BuildContext context) {
    final root = context.findRenderObject();
    if (root is! RenderBox || !root.hasSize) return null;
    final direction = Directionality.of(context);
    _HeroImageGeometry? result;
    var radius = BorderRadius.zero;

    void visit(RenderObject object) {
      if (result != null) return;
      if (object is RenderClipRRect) {
        radius = object.borderRadius.resolve(direction);
      }

      ui.Image? image;
      BoxFit? fit;
      AlignmentGeometry alignment = Alignment.center;
      Rect? gestureRect;
      if (object is ExtendedRenderImage) {
        image = object.image;
        fit = object.fit;
        alignment = object.alignment;
        final gesture = object.gestureDetails;
        if (gesture?.destinationRect != null && gesture?.layoutRect != null) {
          // ExtendedImage stores these in canvas coordinates, including its
          // paint offset. Convert back to the render box's local coordinates.
          gestureRect =
              gesture!.destinationRect!.shift(-gesture.layoutRect!.topLeft);
        }
      } else if (object is RenderImage) {
        image = object.image;
        fit = object.fit;
        alignment = object.alignment;
      }

      if (image != null && object is RenderBox && object.hasSize) {
        final pixels = Size(image.width.toDouble(), image.height.toDouble());
        final resolvedAlignment = alignment.resolve(direction);
        final fitted =
            applyBoxFit(fit ?? BoxFit.scaleDown, pixels, object.size);
        final crop = resolvedAlignment.inscribe(
          fitted.source,
          Offset.zero & pixels,
        );
        final painted = gestureRect ??
            resolvedAlignment.inscribe(
              fitted.destination,
              Offset.zero & object.size,
            );
        if (crop.width <= 0 ||
            crop.height <= 0 ||
            painted.width <= 0 ||
            painted.height <= 0 ||
            !crop.width.isFinite ||
            !crop.height.isFinite ||
            !painted.width.isFinite ||
            !painted.height.isFinite) {
          object.visitChildren(visit);
          return;
        }

        // Expand the cropped source back into the complete pixel plane so the
        // image itself is never stretched to match the viewport's aspect ratio.
        final scaleX = painted.width / crop.width;
        final scaleY = painted.height / crop.height;
        final fullImageRect = Rect.fromLTWH(
          painted.left - crop.left * scaleX,
          painted.top - crop.top * scaleY,
          pixels.width * scaleX,
          pixels.height * scaleY,
        );
        result = _HeroImageGeometry(
          image,
          MatrixUtils.transformRect(object.getTransformTo(root), fullImageRect),
          radius,
        );
        return;
      }

      object.visitChildren(visit);
    }

    visit(root);
    return result;
  }
}

/// Freezes decoded pixels and interpolates image bounds separately from crop.
/// Re-layout of a zoomable image during Hero flight can otherwise change crop.
class _HeroReturnImageMorph extends StatefulWidget {
  const _HeroReturnImageMorph({
    required this.animation,
    required this.image,
    required this.source,
    required this.target,
  });

  final Animation<double> animation;
  final ui.Image image;
  final _HeroImageGeometry source;
  final _HeroImageGeometry target;

  @override
  State<_HeroReturnImageMorph> createState() => _HeroReturnImageMorphState();
}

class _HeroReturnImageMorphState extends State<_HeroReturnImageMorph> {
  @override
  void dispose() {
    widget.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        key: const ValueKey('gallery-return-image-plane'),
        painter: _HeroReturnPainter(
          widget.image,
          widget.animation,
          widget.source,
          widget.target,
        ),
        child: const SizedBox.expand(),
      );
}

class _HeroReturnPainter extends CustomPainter {
  _HeroReturnPainter(this.image, this.animation, this.source, this.target)
      : super(repaint: animation);

  final ui.Image image;
  final Animation<double> animation;
  final _HeroImageGeometry source;
  final _HeroImageGeometry target;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = (1 - animation.value).clamp(0.0, 1.0);
    final rect = Rect.lerp(source.rect, target.rect, progress)!;
    final radius = BorderRadius.lerp(source.radius, target.radius, progress)!;
    canvas.save();
    canvas.clipRRect(radius.toRRect(Offset.zero & size));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeroReturnPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.source != source ||
      oldDelegate.target != target ||
      oldDelegate.animation != animation;
}

/// A transparent route lets the black gallery background fade in behind the
/// Hero flight, so the thumbnail visibly grows into the full-screen image.
class MediaGalleryRoute<T> extends PageRouteBuilder<T> {
  MediaGalleryRoute({required Widget child, super.settings})
      : super(
          opaque: false,
          barrierDismissible: false,
          barrierColor: Colors.black,
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, __, ___) => child,
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
}

// Gallery paging, zoom and dismiss gestures are adapted from Review (MIT);
// Twitter media loading and saving continue to use ReviewX's own models/services.
class MediaPage extends ConsumerStatefulWidget {
  const MediaPage(
      {super.key,
      required this.media,
      required this.index,
      this.author = '',
      this.post,
      this.heroScope,
      this.heroThumbnailUsesCover = false});
  final List<SocialMedia> media;
  final int index;
  final String author;
  final SocialPost? post;
  final Object? heroScope;
  final bool heroThumbnailUsesCover;
  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage>
    with SingleTickerProviderStateMixin {
  late final ExtendedPageController _pages =
      ExtendedPageController(initialPage: widget.index);
  late final PageController _thumbnailController =
      PageController(initialPage: widget.index, viewportFraction: 0.16)
        ..addListener(_syncMainPageToThumbnail);
  final GlobalKey<ExtendedImageSlidePageState> _slidePageKey =
      GlobalKey<ExtendedImageSlidePageState>();
  late int _index = widget.index;
  bool _saving = false, _showChrome = true;
  bool _thumbnailUserScrolling = false, _thumbnailSettling = false;
  int _thumbnailSyncEpoch = 0;

  bool get _hasThumbnailStrip =>
      widget.media.length > 1 &&
      widget.media.every((media) => media.video == null);

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
    if (index != _index && _thumbnailUserScrolling) {
      HapticFeedbackUtil.selection();
    }
    if (mounted) setState(() => _index = index);
    if (!_thumbnailUserScrolling &&
        !_thumbnailSettling &&
        _thumbnailController.hasClients) {
      _thumbnailController.jumpToPage(index);
    }
  }

  void _syncMainPageToThumbnail() {
    if (!_thumbnailUserScrolling ||
        !_thumbnailController.hasClients ||
        !_pages.hasClients) {
      return;
    }
    final page = (_thumbnailController.page ?? _index.toDouble())
        .clamp(0.0, (widget.media.length - 1).toDouble());
    final position = _pages.position;
    final target =
        (position.minScrollExtent + page * position.viewportDimension)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    if ((position.pixels - target).abs() > 0.5) position.jumpTo(target);
  }

  void _settleThumbnailScroll() {
    if (_thumbnailSettling ||
        !_thumbnailController.hasClients ||
        !_pages.hasClients) {
      return;
    }
    final target = (_thumbnailController.page ?? _index.toDouble())
        .round()
        .clamp(0, widget.media.length - 1);
    final epoch = ++_thumbnailSyncEpoch;
    _thumbnailUserScrolling = false;
    _thumbnailSettling = true;
    const duration = Duration(milliseconds: 120);
    unawaited(Future.wait<void>([
      _thumbnailController.animateToPage(target,
          duration: duration, curve: Curves.easeOutCubic),
      _pages.animateToPage(target,
          duration: duration, curve: Curves.easeOutCubic),
    ]).whenComplete(() {
      if (!mounted || epoch != _thumbnailSyncEpoch) return;
      _thumbnailSettling = false;
    }));
  }

  bool _handleThumbnailScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _thumbnailSyncEpoch++;
      _thumbnailSettling = false;
      _thumbnailUserScrolling = true;
    } else if (notification is ScrollEndNotification &&
        _thumbnailUserScrolling) {
      _settleThumbnailScroll();
    }
    return false;
  }

  void _selectThumbnail(int index) {
    if (index == _index) return;
    HapticFeedbackUtil.light();
    _thumbnailSyncEpoch++;
    _thumbnailUserScrolling = false;
    _thumbnailSettling = false;
    if (_thumbnailController.hasClients) {
      _thumbnailController.jumpToPage(index);
    }
    _goTo(index);
  }

  Widget _buildThumbnailStrip() => SizedBox(
        key: const ValueKey('gallery-thumbnail-strip'),
        height: 64,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleThumbnailScroll,
          child: PageView.builder(
            controller: _thumbnailController,
            physics: const ClampingScrollPhysics(),
            pageSnapping: false,
            itemCount: widget.media.length,
            itemBuilder: (context, index) {
              final selected = index == _index;
              return Semantics(
                label: '第 ${index + 1} 张图片',
                selected: selected,
                button: true,
                child: GestureDetector(
                  key: ValueKey('gallery-thumbnail-$index'),
                  onTap: () => _selectThumbnail(index),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(fit: StackFit.expand, children: [
                          ExtendedImage.network(
                            widget.media[index].preview,
                            headers: XRequestHeaders.media,
                            fit: BoxFit.cover,
                            cacheWidth: 160,
                            cache: true,
                          ),
                          if (!selected)
                            ColoredBox(
                                color: Colors.white.withValues(alpha: 0.5)),
                        ]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

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
    _thumbnailController.removeListener(_syncMainPageToThumbnail);
    _thumbnailController.dispose();
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
                      _GalleryGlassIconButton(
                        tooltip: '返回',
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
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
                        _GalleryGlassIconButton(
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
                child: NotificationListener<ScrollStartNotification>(
                  onNotification: (notification) {
                    if (notification.depth == 0 &&
                        notification.dragDetails != null) {
                      _thumbnailSyncEpoch++;
                      _thumbnailUserScrolling = false;
                      _thumbnailSettling = false;
                    }
                    return false;
                  },
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
                        final image = Stack(fit: StackFit.expand, children: [
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
                              minScale: 1.0,
                              animationMinScale: 1.0,
                              maxScale: 8,
                              animationMaxScale: 9,
                              speed: 1,
                              inertialSpeed: 120,
                              initialScale: 1,
                              cacheGesture: false,
                              inPageView: true,
                            ),
                          ),
                        ]);
                        final heroScope = widget.heroScope;
                        final imageWithHero =
                            heroScope != null && index == _index
                                ? Hero(
                                    tag: mediaGalleryHeroTag(
                                      heroScope,
                                      index,
                                      imageAspectRatio:
                                          mediaGalleryImageAspectRatio(media),
                                      thumbnailUsesCover:
                                          widget.heroThumbnailUsesCover,
                                    ),
                                    flightShuttleBuilder:
                                        mediaGalleryHeroFlightShuttleBuilder,
                                    child: image,
                                  )
                                : image;
                        return SizedBox.expand(child: imageWithHero);
                      });
                    },
                  ),
                ),
              ),
              if (_hasThumbnailStrip)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.paddingOf(context).bottom + 32,
                  child: AnimatedOpacity(
                    opacity: _showChrome ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: IgnorePointer(
                      ignoring: !_showChrome,
                      child: _buildThumbnailStrip(),
                    ),
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

class _GalleryGlassIconButton extends StatefulWidget {
  const _GalleryGlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<_GalleryGlassIconButton> createState() =>
      _GalleryGlassIconButtonState();
}

class _GalleryGlassIconButtonState extends State<_GalleryGlassIconButton> {
  static Future<ui.FragmentProgram>? _programFuture;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_programFuture ??= ui.FragmentProgram.fromAsset(
        'shaders/gallery_glass_button.frag',
      ));
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (_) {
      // Keep the blur and translucent surface when shaders are unavailable.
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blur = ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5);
    final shader = _shader;
    final filter = shader == null
        ? blur
        : ui.ImageFilter.compose(
            outer: ui.ImageFilter.shader(shader),
            inner: blur,
          );

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 7,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.08),
                    blurRadius: 5,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: ClipOval(
                clipBehavior: Clip.antiAlias,
                child: BackdropFilter(
                  filter: filter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.grey.shade200.withValues(alpha: 0.30),
                          Colors.grey.shade500.withValues(alpha: 0.20),
                          Colors.grey.shade800.withValues(alpha: 0.36),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.34),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: widget.tooltip,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(48),
              padding: EdgeInsets.zero,
              foregroundColor: Colors.white,
              backgroundColor: Colors.transparent,
              shape: const CircleBorder(),
            ),
            onPressed: widget.onPressed,
            icon: widget.icon,
          ),
        ],
      ),
    );
  }
}
