import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import 'player_backend.dart';

/// [PlayerBackend] implementation backed by `flutter_vlc_player` (libVLC).
///
/// This intentionally mirrors the plugin's own documented usage as closely
/// as possible: construct the controller with `autoPlay: false`, hand it
/// straight to the `VlcPlayer` widget, and call `play`/`seekTo`/etc.
/// directly with no custom readiness gate in front of them. An earlier
/// version of this class tried to be clever and queue commands until
/// `addOnInitListener` fired before running them — that callback turned out
/// not to fire reliably in this app's usage, which meant every command sat
/// in the queue forever and nothing ever played, on both Android and iOS.
/// Direct calls plus [PlayerScreen]'s own bounded wait-and-poll loop (real
/// seconds of `Future.delayed`, giving the native side plenty of time to
/// come up before `play()`/`seek()` are ever called) is simpler and matches
/// what the plugin's README shows working.
class VlcBackend implements PlayerBackend {
  VlcPlayerController? _controller;
  bool _disposed = false;
  bool _everReceivedAnyValue = false;
  Timer? _watchdog;

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
  PlayingState? _lastLoggedState;

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;

    if (!_everReceivedAnyValue) {
      _everReceivedAnyValue = true;
      _watchdog?.cancel();
      debugPrint(
        '[VlcBackend] first value callback received (state=${value.playingState})',
      );
    }

    if (value.playingState != _lastLoggedState) {
      _lastLoggedState = value.playingState;
      debugPrint('[VlcBackend] state -> ${value.playingState}');
    }

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
      debugPrint('[VlcBackend] error: ${value.errorDescription}');
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
    debugPrint('[VlcBackend] open: $url (autoPlay=$autoPlay)');
    final userAgent = httpHeaders['User-Agent'];
    final controller = VlcPlayerController.network(
      url,
      autoPlay: autoPlay,
      hwAcc: HwAcc.full,
      allowBackgroundPlayback: true,
      options: VlcPlayerOptions(
        extras: [
          if (userAgent != null) '--http-user-agent=$userAgent',
          '--network-caching=3000',
        ],
      ),
    );
    _controller = controller;
    _everReceivedAnyValue = false;
    controller.addListener(_onControllerChanged);

    // Watchdog: if libVLC never calls back at all — not a single value
    // change — surface that as a real error instead of leaving the screen
    // sitting there with controls but no video and no explanation.
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 12), () {
      if (_disposed || _everReceivedAnyValue) return;
      debugPrint(
        '[VlcBackend] watchdog: no value callback within 12s for $url',
      );
      _errorCtrl.add(
        'VLC did not respond while opening this stream (no native callback '
        'within 12s). The native VLC engine may have failed to initialize '
        'on this device.',
      );
    });
  }

  @override
  Future<void> play() async {
    debugPrint('[VlcBackend] play()');
    await _controller?.play();
  }

  @override
  Future<void> pause() async {
    debugPrint('[VlcBackend] pause()');
    await _controller?.pause();
  }

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
  Future<void> seek(Duration position) async {
    debugPrint('[VlcBackend] seek($position)');
    await _controller?.seekTo(position);
  }

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
    debugPrint('[VlcBackend] dispose');
    _disposed = true;
    _watchdog?.cancel();
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
      placeholder: const SizedBox.shrink(),
    );
  }
}
