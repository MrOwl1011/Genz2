import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_backend.dart';

/// [PlayerBackend] implementation backed by `media_kit` (libmpv).
class MediaKitBackend implements PlayerBackend {
  MediaKitBackend()
      : _player = Player(
          configuration: const PlayerConfiguration(
            bufferSize: 32 * 1024 * 1024, // 32 MB buffer for streaming
          ),
        ) {
    _controller = VideoController(_player);
    _subs = [
      _player.stream.playing.listen((v) => _playingCtrl.add(v)),
      _player.stream.position.listen((v) => _positionCtrl.add(v)),
      _player.stream.duration.listen((v) => _durationCtrl.add(v)),
      _player.stream.buffering.listen((v) => _bufferingCtrl.add(v)),
      _player.stream.error.listen((v) {
        if (v.isNotEmpty) {
          debugPrint('[MediaKitBackend] error: $v');
          _errorCtrl.add(v);
        }
      }),
      _player.stream.completed.listen((v) {
        if (v) _completedCtrl.add(true);
      }),
      _player.stream.width.listen((v) => _widthCtrl.add(v)),
      _player.stream.height.listen((v) => _heightCtrl.add(v)),
    ];
  }

  final Player _player;
  late final VideoController _controller;
  late final List<StreamSubscription<dynamic>> _subs;

  final _playingCtrl = StreamController<bool>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _bufferingCtrl = StreamController<bool>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _completedCtrl = StreamController<bool>.broadcast();
  final _widthCtrl = StreamController<int?>.broadcast();
  final _heightCtrl = StreamController<int?>.broadcast();

  @override
  Future<void> open({
    required String url,
    required Map<String, String> httpHeaders,
    bool autoPlay = false,
  }) {
    debugPrint('[MediaKitBackend] open: $url (autoPlay=$autoPlay)');
    return _player.open(
      Media(url, httpHeaders: httpHeaders),
      play: autoPlay,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    debugPrint('[MediaKitBackend] dispose');
    for (final s in _subs) {
      await s.cancel();
    }
    try {
      await _player.dispose();
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
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  bool get isPlaying => _player.state.playing;

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
    return Video(
      key: key,
      controller: _controller,
      controls: NoVideoControls,
    );
  }
}
