import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'player_backend.dart';

/// [PlayerBackend] implementation talking directly to a hand-written native
/// iOS platform view (`ios/Runner/NativeVlcPlayerView.swift`) that wraps
/// MobileVLCKit's `VLCMediaPlayer` — bypassing the `flutter_vlc_player`
/// plugin's Dart wrapper entirely. iOS-only; do not construct this on other
/// platforms (see `createPlayerBackend`).
///
/// Every command is deferred until the platform view actually exists
/// (`onPlatformViewCreated`, a core Flutter engine guarantee — not a
/// third-party plugin callback, unlike the trouble we had with
/// `addOnInitListener` in the flutter_vlc_player-based backend). Once the
/// view exists, commands are sent straight through with no further
/// readiness gate: VLCKit's own `play()`/`seekTo()`/etc. are safe to call
/// immediately after media is assigned (confirmed against the reference
/// Swift implementation this native view is modeled on).
class NativeVlcKitBackend implements PlayerBackend {
  static const String _viewType = 'native_vlc_player_view';

  MethodChannel? _methodChannel;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _viewReady = false;
  bool _disposed = false;
  bool _everReceivedAnyEvent = false;
  Timer? _watchdog;

  ({String url, Map<String, String> headers, bool autoPlay})? _pendingOpen;
  final List<void Function()> _pendingCommands = [];

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

  void _onPlatformViewCreated(int id) {
    debugPrint('[NativeVlcKitBackend] platform view created: id=$id');
    final methodChannel = MethodChannel('native_vlc_player_channel_$id');
    final eventChannel = EventChannel('native_vlc_player_events_$id');
    _methodChannel = methodChannel;
    _eventSubscription = eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) =>
          debugPrint('[NativeVlcKitBackend] event channel error: $e'),
    );
    _viewReady = true;

    final pendingOpen = _pendingOpen;
    if (pendingOpen != null) {
      _pendingOpen = null;
      _sendOpen(pendingOpen.url, pendingOpen.headers, pendingOpen.autoPlay);
    }
    final commands = List<void Function()>.from(_pendingCommands);
    _pendingCommands.clear();
    for (final command in commands) {
      command();
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    if (!_everReceivedAnyEvent) {
      _everReceivedAnyEvent = true;
      _watchdog?.cancel();
      debugPrint('[NativeVlcKitBackend] first event received: $event');
    }

    final state = event['state'] as String?;
    final isPlaying = event['isPlaying'] as bool? ?? false;
    final positionMs = (event['positionMs'] as num?)?.toInt() ?? 0;
    final durationMs = (event['durationMs'] as num?)?.toInt() ?? 0;
    final width = (event['width'] as num?)?.toInt();
    final height = (event['height'] as num?)?.toInt();

    _lastPosition = Duration(milliseconds: positionMs);
    _lastDuration = Duration(milliseconds: durationMs);
    _lastIsPlaying = isPlaying;

    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      _playingCtrl.add(isPlaying);
    }
    final buffering = state == 'buffering';
    if (buffering != _wasBuffering) {
      _wasBuffering = buffering;
      _bufferingCtrl.add(buffering);
    }

    _positionCtrl.add(_lastPosition);
    _durationCtrl.add(_lastDuration);

    final w = (width != null && width > 0) ? width : null;
    final h = (height != null && height > 0) ? height : null;
    if (w != _lastWidth) {
      _lastWidth = w;
      _widthCtrl.add(w);
    }
    if (h != _lastHeight) {
      _lastHeight = h;
      _heightCtrl.add(h);
    }

    if (state == 'error') {
      debugPrint('[NativeVlcKitBackend] native reported error state');
      _errorCtrl.add('VLCKit reported a playback error for this stream.');
    }

    if (state == 'ended' && !_completedFired) {
      _completedFired = true;
      _completedCtrl.add(true);
    } else if (state != 'ended') {
      _completedFired = false;
    }
  }

  Future<void> _sendOpen(
    String url,
    Map<String, String> headers,
    bool autoPlay,
  ) async {
    debugPrint('[NativeVlcKitBackend] sending open: $url (autoPlay=$autoPlay)');
    try {
      await _methodChannel?.invokeMethod('open', {
        'url': url,
        'userAgent': headers['User-Agent'],
        'autoPlay': autoPlay,
      });
    } catch (e) {
      debugPrint('[NativeVlcKitBackend] open failed: $e');
      _errorCtrl.add(e.toString());
    }
  }

  void _runOrQueue(String label, void Function() action) {
    if (_viewReady) {
      debugPrint('[NativeVlcKitBackend] $label');
      action();
    } else {
      debugPrint('[NativeVlcKitBackend] $label queued (view not created yet)');
      _pendingCommands.add(action);
    }
  }

  @override
  Future<void> open({
    required String url,
    required Map<String, String> httpHeaders,
    bool autoPlay = false,
  }) async {
    debugPrint('[NativeVlcKitBackend] open: $url (autoPlay=$autoPlay)');
    _everReceivedAnyEvent = false;

    if (_viewReady) {
      await _sendOpen(url, httpHeaders, autoPlay);
    } else {
      _pendingOpen = (url: url, headers: httpHeaders, autoPlay: autoPlay);
    }

    // Watchdog: if the native side never emits a single event — not even
    // one — after a reasonable window, surface that as a real error rather
    // than leaving the screen looking frozen with no explanation.
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 12), () {
      if (_disposed || _everReceivedAnyEvent) return;
      debugPrint(
        '[NativeVlcKitBackend] watchdog: no event within 12s for $url',
      );
      _errorCtrl.add(
        'The native VLCKit player did not respond while opening this stream.',
      );
    });
  }

  @override
  Future<void> play() async =>
      _runOrQueue('play()', () => _methodChannel?.invokeMethod('play'));

  @override
  Future<void> pause() async =>
      _runOrQueue('pause()', () => _methodChannel?.invokeMethod('pause'));

  @override
  Future<void> playOrPause() async {
    if (_lastIsPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async => _runOrQueue(
    'seek($position)',
    () => _methodChannel?.invokeMethod('seek', {
      'positionMs': position.inMilliseconds,
    }),
  );

  @override
  Future<void> setRate(double rate) async => _runOrQueue(
    'setRate($rate)',
    () => _methodChannel?.invokeMethod('setRate', {'rate': rate}),
  );

  @override
  Future<void> stop() async {
    try {
      await _methodChannel?.invokeMethod('stop');
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    debugPrint('[NativeVlcKitBackend] dispose');
    _disposed = true;
    _watchdog?.cancel();
    _pendingCommands.clear();
    try {
      await _methodChannel?.invokeMethod('dispose');
    } catch (_) {}
    await _eventSubscription?.cancel();
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
    return UiKitView(
      key: key,
      viewType: _viewType,
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
