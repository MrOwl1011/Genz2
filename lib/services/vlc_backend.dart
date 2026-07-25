import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import 'player_backend.dart';

/// [PlayerBackend] implementation backed by `flutter_vlc_player` (libVLC).
///
/// Calling `play`/`seekTo`/etc. before libVLC finishes initializing throws
/// (`play() was called on an uninitialized VlcPlayerController` — confirmed
/// in testing, not theoretical), so every command is queued until the
/// controller reports `value.isInitialized == true` and flushed the moment
/// it does. Readiness is read off `controller.value` via the normal
/// `addListener` mechanism (the same one driving every other stream in this
/// class), not the plugin's separate `addOnInitListener` callback — that
/// callback didn't fire reliably in practice and left every command queued
/// forever with nothing ever playing on either platform.
class VlcBackend implements PlayerBackend {
  VlcPlayerController? _controller;
  bool _disposed = false;
  bool _everReceivedAnyValue = false;
  bool _wasInitialized = false;
  Timer? _watchdog;
  final List<void Function(VlcPlayerController)> _pendingCommands = [];

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

  /// Runs [action] now if libVLC has finished initializing, otherwise
  /// queues it to run the instant [_onControllerChanged] observes
  /// `value.isInitialized` flip to true. Calling straight through before
  /// that point throws (confirmed: "play() was called on an uninitialized
  /// VlcPlayerController"), so every command goes through this.
  void _runOrQueue(String label, void Function(VlcPlayerController) action) {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isInitialized) {
      debugPrint('[VlcBackend] $label (initialized)');
      action(controller);
    } else {
      debugPrint('[VlcBackend] $label queued (not initialized yet)');
      _pendingCommands.add(action);
    }
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;

    if (!_everReceivedAnyValue) {
      _everReceivedAnyValue = true;
      _watchdog?.cancel();
      debugPrint(
        '[VlcBackend] first value callback received '
        '(state=${value.playingState}, isInitialized=${value.isInitialized})',
      );
    }

    if (value.isInitialized && !_wasInitialized) {
      _wasInitialized = true;
      debugPrint(
        '[VlcBackend] isInitialized -> true, flushing ${_pendingCommands.length} queued command(s)',
      );
      final commands = List<void Function(VlcPlayerController)>.from(_pendingCommands);
      _pendingCommands.clear();
      for (final command in commands) {
        command(controller);
      }
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
    _wasInitialized = false;
    _pendingCommands.clear();
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
  Future<void> play() async => _runOrQueue('play()', (c) => c.play());

  @override
  Future<void> pause() async => _runOrQueue('pause()', (c) => c.pause());

  @override
  Future<void> playOrPause() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isInitialized && controller.value.isPlaying) {
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
      await _controller?.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    debugPrint('[VlcBackend] dispose');
    _disposed = true;
    _watchdog?.cancel();
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
