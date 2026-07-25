import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import 'player_backend.dart';

/// [PlayerBackend] implementation backed by `flutter_vlc_player` (libVLC).
///
/// The controller can accept `play`/`seekTo`/etc. calls the instant it's
/// constructed, but libVLC itself only actually starts opening the URL once
/// its platform view has mounted and fired `addOnInitListener` — calling a
/// command before that can be silently dropped depending on plugin/platform
/// version. Rather than have [open] block until that fires (which risks
/// hanging forever with zero diagnostics if it never does, or races the
/// widget's own mount timing), every command is queued if native init
/// hasn't completed yet and flushed the moment it does. [open] itself
/// returns as soon as the controller exists, matching the pattern the
/// plugin's own examples use (build the `VlcPlayer` widget immediately;
/// don't wait on it).
class VlcBackend implements PlayerBackend {
  VlcPlayerController? _controller;
  bool _isNativeReady = false;
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
  /// queues it to run the moment [_onNativeReady] fires.
  void _runOrQueue(String label, void Function(VlcPlayerController) action) {
    final controller = _controller;
    if (controller == null) return;
    if (_isNativeReady) {
      debugPrint('[VlcBackend] $label (native ready)');
      action(controller);
    } else {
      debugPrint('[VlcBackend] $label queued (native not ready yet)');
      _pendingCommands.add(action);
    }
  }

  void _onNativeReady() {
    if (_isNativeReady) return;
    _isNativeReady = true;
    final controller = _controller;
    debugPrint(
      '[VlcBackend] native init complete, flushing ${_pendingCommands.length} queued command(s)',
    );
    if (controller != null) {
      for (final command in _pendingCommands) {
        command(controller);
      }
    }
    _pendingCommands.clear();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;

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
      hwAcc: HwAcc.auto,
      allowBackgroundPlayback: true,
      options: VlcPlayerOptions(
        extras: [
          if (userAgent != null) '--http-user-agent=$userAgent',
          '--network-caching=3000',
          // Auto-retry a dropped connection instead of surfacing it as a
          // dead stream — matters most right after a seek, when the old
          // byte-range request is torn down and a new one has to land.
          '--http-reconnect',
        ],
      ),
    );
    _controller = controller;
    _isNativeReady = false;
    _pendingCommands.clear();
    controller.addListener(_onControllerChanged);
    controller.addOnInitListener(() {
      debugPrint('[VlcBackend] onInit fired for $url');
      _onNativeReady();
    });
    // `open()` intentionally does not await native readiness — see class
    // doc. The controller is already valid to hand to buildVideoWidget().
  }

  @override
  Future<void> play() async => _runOrQueue('play()', (c) => c.play());

  @override
  Future<void> pause() async => _runOrQueue('pause()', (c) => c.pause());

  @override
  Future<void> playOrPause() async {
    final controller = _controller;
    if (controller == null) return;
    if (_isNativeReady && controller.value.isPlaying) {
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
    );
  }
}
