import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import 'player_backend.dart';

/// [PlayerBackend] implementation backed by `flutter_vlc_player` (libVLC).
///
/// libVLC only starts initializing once its platform view has actually
/// mounted, so [open] deliberately does the (synchronous) controller setup
/// first and only *awaits* readiness afterwards — by the time that await
/// suspends, [PlayerScreen] has already rebuilt with [buildVideoWidget] in
/// the tree, which is what triggers the native view (and therefore VLC) to
/// come up. This mirrors how `media_kit`'s headless `Player` becomes usable
/// as soon as `open()` resolves, so callers don't need engine-specific code.
class VlcBackend implements PlayerBackend {
  VlcPlayerController? _controller;

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

    if (value.hasError && value.errorDescription.isNotEmpty) {
      _errorCtrl.add(value.errorDescription);
    }

    final ended = value.isEnded || value.playingState == PlayingState.ended;
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
    final userAgent = httpHeaders['User-Agent'];
    final controller = VlcPlayerController.network(
      url,
      autoPlay: autoPlay,
      hwAcc: HwAcc.auto,
      allowBackgroundPlayback: true,
      options: VlcPlayerOptions(
        extras: [
          if (userAgent != null) '--http-user-agent=$userAgent',
          '--network-caching=3000',
        ],
      ),
    );
    _controller = controller;
    controller.addListener(_onControllerChanged);

    // Resolve once the native view finishes initializing (fires once the
    // widget from buildVideoWidget() has mounted), with a safety-net
    // timeout so a bad stream can't hang the caller forever — PlayerScreen
    // surfaces playback failures via errorStream/play() afterwards anyway.
    final ready = Completer<void>();
    controller.addOnInitListener(() {
      if (!ready.isCompleted) ready.complete();
    });
    unawaited(
      Future.delayed(const Duration(seconds: 15), () {
        if (!ready.isCompleted) ready.complete();
      }),
    );
    await ready.future;
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
    try {
      await _controller?.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
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
    if (controller == null) return const SizedBox.shrink();
    return VlcPlayer(
      key: key,
      controller: controller,
      aspectRatio: aspectRatio,
    );
  }
}
