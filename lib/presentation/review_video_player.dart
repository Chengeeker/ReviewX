// Playback gestures, speed/quality menus and HUD adapted from Review (MIT).
// Twitter actions and media persistence use ReviewX's existing repositories.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../core/widgets/cached_network_image.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/services/media_saver.dart';
import '../core/storage/reading_settings.dart';
import '../twitter/auth/app_controller.dart';
import '../twitter/models/social_models.dart';
import 'compose_page.dart';
import 'timeline_page.dart';

enum _DragMode { none, brightness, volume }

enum _HudType { none, brightness, volume, seek, doubleTapSeek }

class ReviewVideoPlayer extends ConsumerStatefulWidget {
  const ReviewVideoPlayer(
      {super.key,
      required this.media,
      required this.active,
      this.post,
      this.author = '',
      this.pageLabel = '',
      this.onPrevious,
      this.onNext,
      this.onToggleChrome,
      this.onFullscreenChanged,
      this.onBottomControlsHeightChanged});
  final SocialMedia media;
  final bool active;
  final SocialPost? post;
  final String author, pageLabel;
  final VoidCallback? onPrevious, onNext;
  final VoidCallback? onToggleChrome;
  final ValueChanged<bool>? onFullscreenChanged;
  final ValueChanged<double>? onBottomControlsHeightChanged;
  @override
  ConsumerState<ReviewVideoPlayer> createState() => _ReviewVideoPlayerState();
}

class _ReviewVideoPlayerState extends ConsumerState<ReviewVideoPlayer>
    with WidgetsBindingObserver {
  static const _mediaChannel = MethodChannel('com.review.x/media');
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  final GlobalKey _bottomControlsKey = GlobalKey();

  // 横竖屏状态
  bool _isLandscape = false;

  // 播放倍速控制
  double _playbackSpeed = 1.0;
  bool _isFastForwarding = false;
  static const List<double> _availableSpeeds = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    3.0
  ];

  // 清晰度控制
  late Map<String, String> _qualityMap;
  String _currentQuality = '高清';

  // 下载与分享状态
  bool _isDownloading = false;

  // 手势与 HUD 状态
  _DragMode _dragMode = _DragMode.none;
  _HudType _hudType = _HudType.none;
  double _hudValue = 0.5; // 亮度或音量比例 (0.0 ~ 1.0)
  int _hudSeekDiff = 0; // 进度差异秒数 (+/-)
  Duration _targetSeekPosition = Duration.zero;
  Offset _verticalDragStartPos = Offset.zero;
  double _startBrightness = 0.5;
  double _startVolume = 0.5;
  double _currentBrightness = 0.5;
  double _currentVolume = 1.0;
  Timer? _hudDismissTimer;
  Offset _lastTapDownPosition = Offset.zero;

  bool _applicationActive = true, _menuOpen = false, _routeObscured = false;
  bool _muted = false, _ownsBrightness = false;
  bool _mayAutoPlay = true;
  double _originalBrightness = -1;
  int _generation = 0;
  int _deviceGeneration = 0;
  Timer? _messageTimer;
  String _message = '';
  late final int _accountEpoch = ref.read(appControllerProvider).epoch;
  String get _selectedUrl =>
      _qualityMap[_currentQuality] ?? widget.media.video!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applicationActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _muted = ref.read(readingProvider)['defaultMutedVideo'] == true;
    _mayAutoPlay = _applicationActive;
    _qualityMap = Map.of(widget.media.videoQualities);
    if (_qualityMap.isEmpty) {
      _qualityMap['原始'] = widget.media.video!;
    }
    _currentQuality = _qualityMap.entries
        .firstWhere((entry) => entry.value == widget.media.video,
            orElse: () => _qualityMap.entries.first)
        .key;
    if (widget.active) {
      _initDeviceLevels();
      _initPlayer();
    }
  }

  Future<void> _initDeviceLevels() async {
    final generation = ++_deviceGeneration;
    try {
      final levels = await _mediaChannel
          .invokeMapMethod<String, dynamic>('getPlayerLevels');
      if (!mounted ||
          _routeObscured ||
          !widget.active ||
          generation != _deviceGeneration ||
          levels == null) {
        return;
      }
      _currentBrightness = (levels['brightness'] as num).toDouble();
      _originalBrightness = (levels['windowBrightness'] as num).toDouble();
      _ownsBrightness = true;
    } on PlatformException {
      /* Device gestures remain optional on other platforms. */
    } on MissingPluginException {
      /* No native window on widget-test platforms. */
    }
  }

  Future<void> _initPlayer(
      {String? overrideUrl,
      Duration? startPosition,
      bool autoPlay = true}) async {
    final generation = ++_generation;
    final previous = _controller;
    previous?.removeListener(_onVideoChanged);
    _controller = null;
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _hasError = false;
      });
    }
    await previous?.dispose();
    if (!mounted || generation != _generation || !widget.active) return;
    final url = overrideUrl ?? _selectedUrl;
    if (!safeMediaUrl(url)) {
      setState(() => _hasError = true);
      return;
    }
    // CDN playback deliberately has no account Cookie or authenticated headers.
    final player = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = player;
    try {
      await player.initialize();
      if (!mounted || generation != _generation) return;
      await player.setLooping(true);
      await player.setPlaybackSpeed(_playbackSpeed);
      await player.setVolume(_muted ? 0 : _currentVolume);
      if (startPosition != null) {
        await player.seekTo(Duration(
            milliseconds: startPosition.inMilliseconds
                .clamp(0, player.value.duration.inMilliseconds)));
      }
      if (!mounted || generation != _generation) return;
      setState(() => _isInitialized = true);
      player.addListener(_onVideoChanged);
      if (autoPlay &&
          _mayAutoPlay &&
          widget.active &&
          _applicationActive &&
          !_routeObscured) {
        await player.play();
      }
      _resetControlsTimer();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
          _showControls = true;
        });
      }
    }
  }

  void _onVideoChanged() {
    final value = _controller?.value;
    if (value?.hasError == true && !_hasError && mounted) {
      setState(() {
        _hasError = true;
        _isInitialized = false;
        _showControls = true;
      });
    }
    // Position updates repaint only the transport's listenable widgets.
    if (value?.isPlaying != true) _hideControlsTimer?.cancel();
  }

  void _restoreBrightness() {
    if (!_ownsBrightness) return;
    _ownsBrightness = false;
    unawaited(_mediaChannel.invokeMethod<void>('restorePlayerBrightness',
        {'brightness': _originalBrightness}).catchError((_) {}));
  }

  void _deactivate() {
    _generation++;
    _deviceGeneration++;
    _hideControlsTimer?.cancel();
    _hudDismissTimer?.cancel();
    _messageTimer?.cancel();
    _message = '';
    final player = _controller;
    _controller = null;
    player?.removeListener(_onVideoChanged);
    if (player != null) unawaited(player.dispose());
    _isInitialized = false;
    _showControls = true;
    _isFastForwarding = false;
    _hudType = _HudType.none;
    _restoreBrightness();
    if (_isLandscape) {
      _isLandscape = false;
      _restorePortraitAndSystemUI();
      widget.onFullscreenChanged?.call(false);
    }
  }

  @override
  void didUpdateWidget(covariant ReviewVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) _deactivate();
    if (widget.active && !oldWidget.active) {
      _mayAutoPlay = _applicationActive;
      _initDeviceLevels();
      _initPlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applicationActive = state == AppLifecycleState.resumed;
    if (!_applicationActive) {
      _mayAutoPlay = false;
      _onLongPressEnd();
      _controller?.pause();
      _hideControlsTimer?.cancel();
      if (mounted) setState(() => _showControls = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deactivate();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    _messageTimer?.cancel();
    setState(() => _message = message);
    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _message = '');
    });
  }

  Future<T?> _showMenu<T>(
      {required BuildContext context,
      required WidgetBuilder builder,
      Color? backgroundColor,
      ShapeBorder? shape}) async {
    _menuOpen = true;
    _hideControlsTimer?.cancel();
    try {
      return await showModalBottomSheet<T>(
          context: context,
          builder: (context) => ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.8),
              child: SingleChildScrollView(child: builder(context))),
          backgroundColor: backgroundColor,
          shape: shape,
          isScrollControlled: true);
    } finally {
      _menuOpen = false;
      if (mounted) _resetControlsTimer();
    }
  }

  void _restorePortraitAndSystemUI() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
  }

  void _toggleOrientation() {
    final nextLandscape = !_isLandscape;
    setState(() {
      _isLandscape = nextLandscape;
    });

    if (nextLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _restorePortraitAndSystemUI();
    }
    widget.onFullscreenChanged?.call(nextLandscape);
    _resetControlsTimer();
  }

  void _reportBottomControlsHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _bottomControlsKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        widget.onBottomControlsHeightChanged?.call(box.size.height);
      }
    });
  }

  Widget _measureBottomControls(Widget controls) {
    if (widget.onBottomControlsHeightChanged == null) return controls;
    if (_bottomControlsKey.currentContext == null) {
      _reportBottomControlsHeight();
    }
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _reportBottomControlsHeight();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        key: _bottomControlsKey,
        child: controls,
      ),
    );
  }

  void _resetControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!_menuOpen &&
        widget.active &&
        _applicationActive &&
        _showControls &&
        _controller != null &&
        _controller!.value.isPlaying) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _controller != null && _controller!.value.isPlaying) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return duration.inHours > 0
        ? '${duration.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  void _togglePlayPause() {
    if (_controller == null ||
        !_isInitialized ||
        !widget.active ||
        !_applicationActive) {
      return;
    }
    HapticFeedbackUtil.light();
    setState(() {
      if (_controller!.value.isPlaying) {
        _mayAutoPlay = false;
        _controller!.pause();
        _showControls = true;
      } else {
        _mayAutoPlay = true;
        _controller!.play();
        _resetControlsTimer();
      }
    });
  }

  // 1(a) 长按左侧或右侧：倍速
  void _onLongPressStart() {
    if (_controller == null ||
        !_isInitialized ||
        !widget.active ||
        !_applicationActive) {
      return;
    }
    if (_controller!.value.isPlaying != true) {
      return;
    }
    _hideControlsTimer?.cancel();
    HapticFeedbackUtil.medium();
    setState(() {
      _isFastForwarding = true;
    });
    _controller?.setPlaybackSpeed(2.0);
  }

  void _onLongPressEnd() {
    if (!_isFastForwarding) return;
    setState(() {
      _isFastForwarding = false;
    });
    _controller?.setPlaybackSpeed(_playbackSpeed);
    _resetControlsTimer();
  }

  // 1(b) 双击左右两侧：快进或快退 10 秒
  void _seekRelative(int deltaSeconds) {
    if (_controller == null ||
        !_isInitialized ||
        !widget.active ||
        !_applicationActive) {
      return;
    }
    HapticFeedbackUtil.light();
    final curPos = _controller!.value.position;
    final totalDur = _controller!.value.duration;
    final target = Duration(
      seconds: (curPos.inSeconds + deltaSeconds).clamp(0, totalDur.inSeconds),
    );
    _controller!.seekTo(target);

    _showHud(
      type: _HudType.doubleTapSeek,
      value: 0,
      diff: deltaSeconds,
      targetPosition: target,
      autoDismissMs: 800,
    );
  }

  // 滑动调节亮度
  void _setBrightness(double value) {
    _currentBrightness = value;
    _mediaChannel.invokeMethod(
        'setBrightness', {'brightness': value}).catchError((_) {});
  }

  // Player gain only: preserve the pre-mute level, never change Android volume.
  void _setVolume(double value) {
    _currentVolume = value;
    _muted = false;
    unawaited(_controller?.setVolume(value).catchError((_) {}));
  }

  void _showHud({
    required _HudType type,
    double value = 0,
    int diff = 0,
    Duration targetPosition = Duration.zero,
    int autoDismissMs = 600,
  }) {
    _hudDismissTimer?.cancel();
    setState(() {
      _hudType = type;
      _hudValue = value;
      _hudSeekDiff = diff;
      _targetSeekPosition = targetPosition;
    });
    if (autoDismissMs > 0) {
      _hudDismissTimer = Timer(Duration(milliseconds: autoDismissMs), () {
        if (mounted) {
          setState(() {
            _hudType = _HudType.none;
          });
        }
      });
    }
  }

  void _showSpeedMenu() {
    _showMenu(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    '播放倍速',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                ..._availableSpeeds.reversed.map((speed) {
                  final isSelected = _playbackSpeed == speed;
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${speed}X',
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20)
                        : null,
                    onTap: () {
                      setState(() {
                        _playbackSpeed = speed;
                      });
                      _controller?.setPlaybackSpeed(speed);
                      Navigator.pop(ctx);
                      _toast('已切换至 ${speed}X 倍速');
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // 弹出画质选择菜单
  void _showQualityMenu() {
    if (_qualityMap.isEmpty) {
      _toast('暂无其他清晰度可选');
      return;
    }

    _showMenu(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    '清晰度选择',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                ..._qualityMap.entries.map((entry) {
                  final qName = entry.key;
                  final qUrl = entry.value;
                  final isSelected = _currentQuality == qName;

                  return ListTile(
                    dense: true,
                    title: Text(
                      qName,
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (isSelected) return;

                      final savedPos =
                          _controller?.value.position ?? Duration.zero;
                      final wasPlaying = _controller?.value.isPlaying ?? true;

                      setState(() {
                        _currentQuality = qName;
                      });

                      _initPlayer(
                        overrideUrl: qUrl,
                        startPosition: savedPos,
                        autoPlay: wasPlaying,
                      );
                      _toast('已切换至 $qName');
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _performDownloadVideo() async {
    if (_isDownloading) return;
    final settings = ref.read(readingProvider);
    final account = ref.read(appControllerProvider);
    final folder = settings['storageFolder'] == 'author'
        ? widget.author
        : settings['storageFolder'] == 'me'
            ? account.me?.handle ?? ''
            : '';
    final media =
        SocialMedia(preview: widget.media.preview, video: _selectedUrl);
    setState(() => _isDownloading = true);
    try {
      await MediaSaver.save(media, folder);
      _toast('已保存到系统相册');
    } catch (_) {
      _toast('视频保存失败，请检查网络和相册权限后重试');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _performShareVideo() async {
    await _controller?.pause();
    try {
      await _mediaChannel.invokeMethod<void>('shareText',
          {'text': widget.post?.url ?? _selectedUrl, 'title': '分享视频'});
    } catch (_) {
      await Clipboard.setData(
          ClipboardData(text: widget.post?.url ?? _selectedUrl));
      _toast('链接已复制');
    }
  }

  Future<void> _navigate(Widget page) async {
    _routeObscured = true;
    _mayAutoPlay = false;
    _restoreBrightness();
    await _controller?.pause();
    if (!mounted) return;
    if (_isLandscape) _toggleOrientation();
    _hideControlsTimer?.cancel();
    try {
      await Navigator.push(
          context, MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      _routeObscured = false;
      if (mounted) {
        if (widget.active) {
          _initDeviceLevels();
        }
        setState(() => _showControls = true);
      }
    }
  }

  Future<void> _comment(SocialPost post) async {
    final compose = await _showMenu<bool>(
        context: context,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: const Text('查看评论'),
                  onTap: () => Navigator.pop(context, false)),
              ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('发表评论'),
                  onTap: () => Navigator.pop(context, true)),
            ])));
    if (!mounted || compose == null) return;
    await _navigate(
        compose ? ComposePage(reply: post) : PostDetailPage(post: post));
  }

  Future<void> _act(SocialPost post, String action) async {
    final controller = ref.read(appControllerProvider);
    if (controller.epoch != _accountEpoch ||
        !controller.loggedIn ||
        controller.actionBlocked(post.id)) {
      return;
    }
    try {
      if (action == 'bookmark') {
        await controller.bookmark(post);
      } else {
        await controller.act(post, like: action == 'like');
      }
    } catch (error) {
      _toast('$error');
    }
  }

  Widget _postActions() {
    final raw = widget.post;
    if (raw == null) return const SizedBox.shrink();
    final app = ref.watch(appControllerProvider);
    final post = app.effective(raw);
    final disabled = !app.loggedIn ||
        app.epoch != _accountEpoch ||
        app.actionBlocked(post.id);
    String compact(int value) => value >= 1000000
        ? '${(value / 1000000).toStringAsFixed(1)}M'
        : value >= 1000
            ? '${(value / 1000).toStringAsFixed(1)}K'
            : '$value';
    Widget button(String label, IconData icon, VoidCallback? onTap,
            {String? count, Color? color}) =>
        Expanded(
            child: Tooltip(
                message: label,
                child: TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: color ?? Colors.white,
                        disabledForegroundColor: Colors.white38,
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 4)),
                    onPressed: onTap,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 23),
                          if (count != null) ...[
                            const SizedBox(width: 5),
                            Flexible(
                                child: Text(count,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis))
                          ],
                        ]))));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        button('评论', Icons.chat_bubble_outline, () => _comment(post),
            count: compact(post.replies)),
        button(post.reposted ? '取消转发' : '转发', Icons.repeat,
            disabled ? null : () => _act(post, 'repost'),
            count: compact(post.reposts),
            color: post.reposted ? Colors.greenAccent : null),
        button(
            post.liked ? '取消喜欢' : '喜欢',
            post.liked ? Icons.favorite : Icons.favorite_border,
            disabled ? null : () => _act(post, 'like'),
            count: compact(post.likes),
            color: post.liked ? Colors.pinkAccent : null),
        button(
            post.bookmarked ? '移除书签' : '加入书签',
            post.bookmarked ? Icons.bookmark : Icons.bookmark_outline,
            disabled ? null : () => _act(post, 'bookmark'),
            color: post.bookmarked ? Colors.lightBlueAccent : null),
      ]),
      if (app.isUncertain(post.id))
        const Text('操作结果待核对，请在帖子详情刷新',
            style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
    ]);
  }

  Widget _transportControls(
          {required bool canPlay,
          required bool isPlaying,
          required String timeLabel}) =>
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            IconButton(
                tooltip: canPlay ? (isPlaying ? '暂停' : '播放') : '视频加载中',
                onPressed: canPlay ? _togglePlayPause : null,
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white)),
            SizedBox(
                width: MediaQuery.textScalerOf(context).scale(80),
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(timeLabel,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)))),
            SizedBox(
                width: MediaQuery.textScalerOf(context).scale(60),
                child: TextButton(
                    style: TextButton.styleFrom(
                        minimumSize: const Size(44, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: _showSpeedMenu,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('${_playbackSpeed}X',
                            style: const TextStyle(color: Colors.white))))),
            SizedBox(
                width: MediaQuery.textScalerOf(context).scale(60),
                child: TextButton(
                    style: TextButton.styleFrom(
                        minimumSize: const Size(44, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: _qualityMap.length > 1 ? _showQualityMenu : null,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_currentQuality,
                            style: const TextStyle(color: Colors.white70))))),
            IconButton(
                tooltip: _isLandscape ? '竖屏' : '横屏',
                onPressed: _toggleOrientation,
                icon: Icon(
                    _isLandscape ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white)),
          ]);

  Widget _transport(VideoPlayerController? player) {
    Widget progressPlaceholder() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: SizedBox(
            height: 5,
            child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white12))));

    if (!_isInitialized || player == null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        progressPlaceholder(),
        _transportControls(
            canPlay: false, isPlaying: false, timeLabel: '--:-- / --:--'),
      ]);
    }

    return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: player,
        builder: (context, value, _) =>
            Column(mainAxisSize: MainAxisSize.min, children: [
              VideoProgressIndicator(player,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white12)),
              _transportControls(
                  canPlay: true,
                  isPlaying: value.isPlaying,
                  timeLabel:
                      '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}'),
            ]));
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
          canPop: !_isLandscape,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _isLandscape) _toggleOrientation();
          },
          child: Scaffold(
              backgroundColor: Colors.black,
              body: LayoutBuilder(builder: (context, constraints) {
                final screenWidth = constraints.maxWidth,
                    screenHeight = constraints.maxHeight;
                final player = _controller;
                return Stack(alignment: Alignment.center, children: [
                  if (_isInitialized && player != null)
                    Center(
                        child: AspectRatio(
                            aspectRatio: player.value.aspectRatio > 0
                                ? player.value.aspectRatio
                                : 16 / 9,
                            child: RepaintBoundary(child: VideoPlayer(player))))
                  else if (widget.active && widget.media.preview.isNotEmpty)
                    Center(
                        child: CachedNetworkImage(widget.media.preview,
                            fit: BoxFit.contain)),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        _lastTapDownPosition = details.localPosition;
                      },
                      onDoubleTapDown: (details) {
                        _lastTapDownPosition = details.localPosition;
                      },
                      onTap: () {
                        HapticFeedbackUtil.light();
                        setState(() {
                          _showControls = !_showControls;
                        });
                        if (!_isLandscape) widget.onToggleChrome?.call();
                        _resetControlsTimer();
                      },
                      onDoubleTap: () {
                        final x = _lastTapDownPosition.dx;
                        // 1(c) 双击中间：播放/暂停
                        // 1(b) 双击左右两侧：快退或快进 10 秒
                        if (x < screenWidth * 0.35) {
                          _seekRelative(-10);
                        } else if (x > screenWidth * 0.65) {
                          _seekRelative(10);
                        } else {
                          _togglePlayPause();
                        }
                      },
                      onLongPressStart: (details) {
                        final x = details.localPosition.dx;
                        // 1(a) 长按左侧或右侧：倍速
                        if (x < screenWidth * 0.45 || x > screenWidth * 0.55) {
                          _onLongPressStart();
                        }
                      },
                      onLongPressEnd: (_) => _onLongPressEnd(),
                      onLongPressCancel: _onLongPressEnd,
                      onVerticalDragStart: (details) {
                        _hideControlsTimer?.cancel();
                        _verticalDragStartPos = details.localPosition;
                        _dragMode = _DragMode.none;
                        _startBrightness = _currentBrightness;
                        _startVolume = _currentVolume;
                      },
                      onVerticalDragUpdate: (details) {
                        final dy =
                            details.localPosition.dy - _verticalDragStartPos.dy;

                        if (_dragMode == _DragMode.none && dy.abs() > 14) {
                          _dragMode = _verticalDragStartPos.dx < screenWidth / 2
                              ? _DragMode.brightness
                              : _DragMode.volume;
                        }

                        if (_dragMode == _DragMode.brightness) {
                          final delta = -dy / (screenHeight * 0.65);
                          final nextVal =
                              (_startBrightness + delta).clamp(0.01, 1.0);
                          _setBrightness(nextVal);
                          _showHud(
                              type: _HudType.brightness,
                              value: nextVal,
                              autoDismissMs: 0);
                        } else if (_dragMode == _DragMode.volume) {
                          final delta = -dy / (screenHeight * 0.65);
                          final nextVal =
                              (_startVolume + delta).clamp(0.0, 1.0);
                          _setVolume(nextVal);
                          _showHud(
                              type: _HudType.volume,
                              value: nextVal,
                              autoDismissMs: 0);
                        }
                      },
                      onVerticalDragCancel: () {
                        _dragMode = _DragMode.none;
                        _showHud(type: _HudType.none);
                        _resetControlsTimer();
                      },
                      onVerticalDragEnd: (_) {
                        _resetControlsTimer();
                        _dragMode = _DragMode.none;
                        _showHud(
                          type: _hudType,
                          value: _hudValue,
                          diff: _hudSeekDiff,
                          targetPosition: _targetSeekPosition,
                          autoDismissMs: 600,
                        );
                      },
                    ),
                  ),
                  IgnorePointer(child: _buildGestureHudOverlay()),
                  if (_isInitialized && player != null)
                    ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: player,
                        builder: (context, value, _) => IgnorePointer(
                            child: value.isBuffering && value.isPlaying
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : const SizedBox.shrink())),
                  if (_message.isNotEmpty)
                    Positioned(
                        top: MediaQuery.paddingOf(context).top + 64,
                        left: 16,
                        right: 16,
                        child: IgnorePointer(
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(16)),
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(_message,
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white)))))),
                  if (_isFastForwarding)
                    Positioned(
                        top: MediaQuery.paddingOf(context).top + 56,
                        child: const IgnorePointer(
                            child: Chip(label: Text('2.0X 倍速快进中')))),
                  if (_hasError)
                    Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('视频加载失败，请重试',
                          style: TextStyle(color: Colors.white)),
                      FilledButton(
                          onPressed: () => _initPlayer(),
                          child: const Text('重试')),
                    ]))
                  else if (!_isInitialized && widget.active)
                    const IgnorePointer(
                        child: CircularProgressIndicator(color: Colors.white)),
                  if (_showControls)
                    Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                            bottom: false,
                            child: Container(
                                color: Colors.black54,
                                child: Row(children: [
                                  IconButton(
                                      tooltip: '返回',
                                      color: Colors.white,
                                      icon: const Icon(Icons.arrow_back),
                                      onPressed: () {
                                        if (_isLandscape) {
                                          _toggleOrientation();
                                        } else {
                                          Navigator.pop(context);
                                        }
                                      }),
                                  Expanded(
                                      child: Text(
                                          widget.post?.author.name ??
                                              widget.author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white))),
                                  if (widget.pageLabel.isNotEmpty)
                                    Text(widget.pageLabel,
                                        style: const TextStyle(
                                            color: Colors.white70)),
                                  if (widget.onPrevious != null)
                                    IconButton(
                                        tooltip: '上一个媒体',
                                        onPressed: widget.onPrevious,
                                        icon: const Icon(Icons.chevron_left,
                                            color: Colors.white)),
                                  if (widget.onNext != null)
                                    IconButton(
                                        tooltip: '下一个媒体',
                                        onPressed: widget.onNext,
                                        icon: const Icon(Icons.chevron_right,
                                            color: Colors.white)),
                                  IconButton(
                                      tooltip: '保存视频',
                                      onPressed: _isDownloading
                                          ? null
                                          : _performDownloadVideo,
                                      icon: _isDownloading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : const Icon(Icons.download,
                                              color: Colors.white)),
                                  IconButton(
                                      tooltip: '分享视频',
                                      onPressed: _performShareVideo,
                                      icon: const Icon(Icons.share,
                                          color: Colors.white)),
                                ])))),
                  if (_showControls)
                    Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _measureBottomControls(Container(
                            decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                  Colors.black,
                                  Colors.black87,
                                  Colors.transparent
                                ])),
                            padding: EdgeInsets.fromLTRB(12, 12, 12,
                                MediaQuery.paddingOf(context).bottom + 8),
                            child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxHeight: screenHeight * 0.55),
                                child: SingleChildScrollView(
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                      _postActions(),
                                      _transport(player),
                                    ])))))),
                ]);
              }))));

  Widget _buildGestureHudOverlay() {
    if (_hudType == _HudType.none) return const SizedBox.shrink();

    Widget content;
    switch (_hudType) {
      case _HudType.brightness:
        final pct = (_hudValue * 100).toInt();
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pct > 50
                  ? Icons.brightness_7_rounded
                  : Icons.brightness_4_rounded,
              color: Colors.amberAccent,
              size: 26,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _hudValue,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$pct%',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ],
        );
        break;

      case _HudType.volume:
        final pct = (_hudValue * 100).toInt();
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pct == 0
                  ? Icons.volume_off_rounded
                  : (pct > 50
                      ? Icons.volume_up_rounded
                      : Icons.volume_down_rounded),
              color: Colors.cyanAccent,
              size: 26,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _hudValue,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$pct%',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ],
        );
        break;

      case _HudType.seek:
        final diffStr =
            _hudSeekDiff >= 0 ? '+${_hudSeekDiff}s' : '${_hudSeekDiff}s';
        final totalDur = _controller?.value.duration ?? Duration.zero;
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hudSeekDiff >= 0
                  ? Icons.fast_forward_rounded
                  : Icons.fast_rewind_rounded,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 6),
            Text(
              '${_formatDuration(_targetSeekPosition)} / ${_formatDuration(totalDur)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              '[$diffStr]',
              style: TextStyle(
                color: _hudSeekDiff >= 0
                    ? Colors.greenAccent
                    : Colors.orangeAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        );
        break;

      case _HudType.doubleTapSeek:
        final diffStr = _hudSeekDiff >= 0 ? '+10s' : '-10s';
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hudSeekDiff >= 0
                  ? Icons.forward_10_rounded
                  : Icons.replay_10_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              diffStr,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ],
        );
        break;

      default:
        return const SizedBox.shrink();
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 16,
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}
