import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../core/build_flavor.dart' show kIsTv;
import 'player_backend.dart';

/// [PlayerBackend] implementation backed by `video_player` (ExoPlayer on
/// Android). Android-only; iOS uses [NativeVlcKitBackend] instead.
///
/// The `video_player` package's Android implementation is ExoPlayer, which
/// handles HLS/DASH/RTSP natively, hardware-accelerated by default. It
/// initializes asynchronously — [open] creates the controller and starts
/// initialization, and we defer play/seek/etc. until initialization completes
/// by queueing commands (same pattern as the old VLC backend).
class ExoPlayerBackend implements PlayerBackend {
  VideoPlayerController? _controller;
  bool _disposed = false;
  bool _initialized = false;
  Timer? _watchdog;
  Timer? _pollingTimer;
  final List<void Function(VideoPlayerController)> _pendingCommands = [];

  final _playingCtrl = StreamController<bool>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _bufferingCtrl = StreamController<bool>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _completedCtrl = StreamController<bool>.broadcast();
  final _widthCtrl = StreamController<int?>.broadcast();
  final _heightCtrl = StreamController<int?>.broadcast();

  bool _wasPlaying = false;
  bool _wasBuffering = false;
  bool _completedFired = false;
  int? _lastWidth;
  int? _lastHeight;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  bool _lastIsPlaying = false;

  /// Runs [action] now if the controller has finished initializing, otherwise
  /// queues it to run the instant initialization completes.
  void _runOrQueue(String label, void Function(VideoPlayerController) action) {
    final controller = _controller;
    if (controller == null) return;
    if (_initialized) {
      debugPrint('[ExoPlayerBackend] $label (initialized)');
      action(controller);
    } else {
      debugPrint('[ExoPlayerBackend] $label queued (not initialized yet)');
      _pendingCommands.add(action);
    }
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || _disposed) return;
    final value = controller.value;

    final isPlaying = value.isPlaying;
    _lastIsPlaying = isPlaying;
    _lastPosition = value.position;
    _lastDuration = value.duration;

    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      _playingCtrl.add(isPlaying);
    }

    final buffering = value.isBuffering;
    if (buffering != _wasBuffering) {
      _wasBuffering = buffering;
      _bufferingCtrl.add(buffering);
    }

    _positionCtrl.add(value.position);
    _durationCtrl.add(value.duration);

    final w = value.size.width > 0 ? value.size.width.round() : null;
    final h = value.size.height > 0 ? value.size.height.round() : null;
    if (w != _lastWidth) {
      _lastWidth = w;
      _widthCtrl.add(w);
    }
    if (h != _lastHeight) {
      _lastHeight = h;
      _heightCtrl.add(h);
    }

    if (value.hasError &&
        value.errorDescription != null &&
        value.errorDescription!.isNotEmpty) {
      debugPrint('[ExoPlayerBackend] error: ${value.errorDescription}');
      _errorCtrl.add(value.errorDescription!);
    }

    final ended = value.isCompleted;
    if (ended && !_completedFired) {
      _completedFired = true;
      _completedCtrl.add(true);
    } else if (!ended) {
      _completedFired = false;
    }
  }

  @override
  Future<void> open({
    required String url,
    required Map<String, String> httpHeaders,
    bool autoPlay = false,
  }) async {
    debugPrint('[ExoPlayerBackend] open: $url (autoPlay=$autoPlay)');

    // Downloaded media is opened via a `file://` URI (see DownloadsProvider)
    // — those need the local-file constructor instead of the network one,
    // which would otherwise try to treat the path as an HTTP data source.
    final uri = Uri.parse(url);
    final controller = uri.isScheme('file')
        ? VideoPlayerController.file(
            File.fromUri(uri),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
              allowBackgroundPlayback: true,
            ),
          )
        : VideoPlayerController.networkUrl(
            uri,
            httpHeaders: httpHeaders,
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
              allowBackgroundPlayback: true,
            ),
          );
    _controller = controller;
    _initialized = false;
    _pendingCommands.clear();
    controller.addListener(_onControllerChanged);

    try {
      // No bound otherwise: a dead/unresponsive source (or, on TV, a
      // decoder slot still tied up by a prior instance) leaves
      // initialize() simply never resolving, which is exactly what a
      // "stuck on Connecting forever" channel looks like from the caller's
      // side. 20s is generous enough for a slow-but-real IPTV connect
      // (manifest negotiation is routinely slower than VOD CDNs) while
      // still giving up in bounded time.
      await controller.initialize().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
          'Timed out connecting to this stream after 20s',
        ),
      );
      _initialized = true;
      debugPrint(
        '[ExoPlayerBackend] initialized: '
        '${controller.value.size.width.round()}x${controller.value.size.height.round()}, '
        'duration=${controller.value.duration}',
      );

      // Flush queued commands
      final commands = List<void Function(VideoPlayerController)>.from(
        _pendingCommands,
      );
      _pendingCommands.clear();
      for (final command in commands) {
        command(controller);
      }

      // Start position polling — video_player's listener doesn't fire as
      // frequently as VLC's, so we supplement it with a periodic poll to
      // keep the seek bar and position display updating smoothly.
      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_disposed || _controller == null) return;
        _onControllerChanged();
      });

      if (autoPlay) {
        // TV: give the stream a head start before the first frame plays,
        // rather than starting the instant ExoPlayer reports "initialized"
        // (which only means the format/duration are known, not that
        // there's any real cushion buffered yet). IPTV sources are
        // frequently higher-latency/less consistent than typical VOD CDNs,
        // and starting with ~zero buffer is what turns that into an
        // immediate stutter/rebuffer right at playback start. The
        // `video_player` plugin doesn't expose ExoPlayer's LoadControl to
        // configure this natively, so this polls the buffered ranges it
        // does expose instead. Phone is left as-is (starts immediately) —
        // not the behavior reported as a problem, and phones are typically
        // on lower-latency, more consistent connections than a TV box.
        if (kIsTv) await _waitForInitialBuffer(controller);
        await controller.play();
      }
    } catch (e) {
      debugPrint('[ExoPlayerBackend] initialization failed: $e');
      _errorCtrl.add(e.toString());
      return;
    }

    // Watchdog: if we got past initialize() but never actually see any
    // frames / position movement, surface that.
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 12), () {
      if (_disposed) return;
      if (_lastDuration.inMilliseconds == 0 &&
          _lastPosition.inMilliseconds == 0) {
        debugPrint(
          '[ExoPlayerBackend] watchdog: no progress within 12s for $url',
        );
        _errorCtrl.add(
          'ExoPlayer did not respond while opening this stream. '
          'The stream may be unavailable or in an unsupported format.',
        );
      }
    });
  }

  /// Polls the controller's already-buffered ranges (there's no push-based
  /// signal for this) until roughly 1s is buffered ahead of the playback
  /// position, or [timeout] passes — whichever comes first, so a source
  /// that never buffers well doesn't delay playback start indefinitely and
  /// just falls back to today's immediate-play behavior.
  Future<void> _waitForInitialBuffer(
    VideoPlayerController controller, {
    Duration target = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      final position = controller.value.position;
      final bufferedAhead = controller.value.buffered
          .where((range) => range.start <= position && range.end > position)
          .fold<Duration>(
            Duration.zero,
            (acc, range) =>
                range.end - position > acc ? range.end - position : acc,
          );
      if (bufferedAhead >= target) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  Future<void> play() async => _runOrQueue('play()', (c) => c.play());

  @override
  Future<void> pause() async => _runOrQueue('pause()', (c) => c.pause());

  @override
  Future<void> playOrPause() async {
    final controller = _controller;
    if (controller == null) return;
    if (_initialized && controller.value.isPlaying) {
      await controller.pause();
    } else {
      _runOrQueue('playOrPause()->play()', (c) => c.play());
    }
  }

  @override
  Future<void> seek(Duration position) async =>
      _runOrQueue('seek($position)', (c) => c.seekTo(position));

  @override
  Future<void> setRate(double rate) async =>
      _runOrQueue('setRate($rate)', (c) => c.setPlaybackSpeed(rate));

  @override
  Future<void> stop() async {
    try {
      await _controller?.pause();
      await _controller?.seekTo(Duration.zero);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    debugPrint('[ExoPlayerBackend] dispose');
    _disposed = true;
    _watchdog?.cancel();
    _pollingTimer?.cancel();
    _pendingCommands.clear();
    _controller?.removeListener(_onControllerChanged);
    try {
      await _controller?.dispose();
    } catch (_) {}
    await Future.wait([
      _playingCtrl.close(),
      _positionCtrl.close(),
      _durationCtrl.close(),
      _bufferingCtrl.close(),
      _errorCtrl.close(),
      _completedCtrl.close(),
      _widthCtrl.close(),
      _heightCtrl.close(),
    ]);
  }

  @override
  Duration get position => _lastPosition;

  @override
  Duration get duration => _lastDuration;

  @override
  bool get isPlaying => _lastIsPlaying;

  @override
  Stream<bool> get playingStream => _playingCtrl.stream;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration> get durationStream => _durationCtrl.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingCtrl.stream;

  @override
  Stream<String> get errorStream => _errorCtrl.stream;

  @override
  Stream<bool> get completedStream => _completedCtrl.stream;

  @override
  Stream<int?> get widthStream => _widthCtrl.stream;

  @override
  Stream<int?> get heightStream => _heightCtrl.stream;

  @override
  Widget buildVideoWidget({Key? key, required double aspectRatio}) {
    final controller = _controller;
    if (controller == null || !_initialized) return const SizedBox.shrink();
    return VideoPlayer(controller, key: key);
  }
}
