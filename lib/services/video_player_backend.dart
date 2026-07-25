import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'player_backend.dart';

/// [PlayerBackend] implementation backed by the official `video_player`
/// package — AVPlayer on iOS/macOS, ExoPlayer on Android.
///
/// Unlike VLC, `initialize()` is an explicit call that only resolves once
/// the controller is genuinely ready to accept `play`/`seekTo`/etc. — no
/// queueing or polling needed here; [open] simply awaits it, matching
/// [MediaKitBackend]'s "ready once open() resolves" contract exactly.
///
/// Caveat worth knowing when comparing engines: AVPlayer has excellent
/// native HLS (`.m3u8`) support (it's Apple's own reference implementation)
/// and handles MP4 well, but has limited/inconsistent support for raw
/// MPEG-TS over plain HTTP, which some Xtream panels use for live and even
/// VOD. If a stream plays in VLC/Media Kit but fails here, that's usually
/// why — not a bug in this backend.
class VideoPlayerBackend implements PlayerBackend {
  VideoPlayerController? _controller;

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

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;

    if (value.isPlaying != _wasPlaying) {
      _wasPlaying = value.isPlaying;
      _playingCtrl.add(value.isPlaying);
    }
    if (value.isBuffering != _wasBuffering) {
      _wasBuffering = value.isBuffering;
      _bufferingCtrl.add(value.isBuffering);
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

    if (value.hasError) {
      final desc = value.errorDescription ?? 'Unknown AVPlayer/ExoPlayer error';
      debugPrint('[VideoPlayerBackend] error: $desc');
      _errorCtrl.add(desc);
    }

    if (value.isCompleted && !_completedFired) {
      _completedFired = true;
      _completedCtrl.add(true);
    } else if (!value.isCompleted) {
      _completedFired = false;
    }
  }

  @override
  Future<void> open({
    required String url,
    required Map<String, String> httpHeaders,
    bool autoPlay = false,
  }) async {
    debugPrint('[VideoPlayerBackend] open: $url (autoPlay=$autoPlay)');
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: httpHeaders,
    );
    _controller = controller;
    controller.addListener(_onControllerChanged);

    try {
      await controller.initialize();
      debugPrint(
        '[VideoPlayerBackend] initialize() complete (duration=${controller.value.duration})',
      );
    } catch (e) {
      debugPrint('[VideoPlayerBackend] initialize() failed: $e');
      _errorCtrl.add(e.toString());
      rethrow;
    }

    if (autoPlay) {
      await controller.play();
    }
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> playOrPause() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  Future<void> seek(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setRate(double rate) async => _controller?.setPlaybackSpeed(rate);

  @override
  Future<void> stop() async {
    // video_player has no explicit stop(); every call site pauses/disposes
    // right after this anyway, so pausing is sufficient cleanup.
    try {
      await _controller?.pause();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    debugPrint('[VideoPlayerBackend] dispose');
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
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

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
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return VideoPlayer(controller, key: key);
  }
}
