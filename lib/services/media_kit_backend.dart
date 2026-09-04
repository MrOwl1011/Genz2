import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_backend.dart';

/// Desktop playback, backed by libmpv via `media_kit`.
///
/// Windows has neither of the other two engines available to it: the iOS
/// backend is MobileVLCKit (an iOS-only pod, see native_vlc_player's
/// pubspec — it declares no other platform), and `video_player` has no
/// Windows implementation at all, so the Android path would fail at
/// runtime rather than at build time. libmpv is the usual answer for
/// Flutter desktop video and, being the engine mpv itself uses, handles the
/// HLS/TS streams IPTV panels serve on the same terms VLC does.
///
/// [MediaKit.ensureInitialized] must have run before the first instance is
/// constructed — see main.dart, which calls it once at startup.
class MediaKitBackend implements PlayerBackend {
  MediaKitBackend() {
    _player = Player();
    _controller = VideoController(_player);
  }

  late final Player _player;
  late final VideoController _controller;

  @override
  Future<void> open({
    required String url,
    required Map<String, String> httpHeaders,
    bool autoPlay = false,
  }) async {
    // Headers matter here for the same reason they do on the other
    // backends: panels commonly gate streams on a recognized player
    // User-Agent (see kIptvUserAgent).
    await _player.open(Media(url, httpHeaders: httpHeaders), play: autoPlay);
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
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<int?> get widthStream => _player.stream.width;

  @override
  Stream<int?> get heightStream => _player.stream.height;

  @override
  Widget buildVideoWidget({Key? key, required double aspectRatio}) {
    // No explicit aspect ratio passed through: unlike the VLC backend, which
    // needs one to size its texture, Video sizes itself from the stream's
    // own dimensions and the caller already wraps this in its own
    // AspectRatio (see PlayerScreen._buildVideoLayer).
    return Video(
      key: key,
      controller: _controller,
      // The app draws every control itself, on every platform.
      controls: NoVideoControls,
      fill: const Color(0xFF000000),
    );
  }
}
