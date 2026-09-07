import 'dart:async';

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
    _positionWatch = _player.stream.position.listen((position) {
      // One position reading that is clearly *not* at the end is enough to
      // prove the newly-opened media is the one now reporting state.
      final duration = _player.state.duration;
      if (duration > Duration.zero && duration - position > _endTolerance) {
        _playbackStartedSinceOpen = true;
      }

      // A seek is finished once playback actually arrives near where it was
      // sent. Until then libmpv's completion flag can't be trusted.
      final pending = _pendingSeekTarget;
      if (pending != null && (position - pending).abs() <= _seekSettleWindow) {
        _clearPendingSeek();
      }
    });
  }

  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<Duration>? _positionWatch;

  /// How close to [duration] counts as having reached the end. Generous
  /// because libmpv stops emitting positions slightly before EOF on some
  /// streams, so an exact comparison would never match.
  static const Duration _endTolerance = Duration(seconds: 5);

  /// False from the moment [open] is called until the new media reports a
  /// position that isn't already at the end. See [completedStream].
  bool _playbackStartedSinceOpen = false;

  /// How close playback has to land to a requested seek before the seek is
  /// treated as finished.
  static const Duration _seekSettleWindow = Duration(seconds: 2);

  /// Where the in-flight [seek] was aimed, or null when none is pending.
  /// Completion is suppressed while this is set — see [completedStream].
  Duration? _pendingSeekTarget;

  /// Releases the completion block even if playback never reaches the
  /// target, so an unseekable stream can't disable auto-advance for the
  /// rest of the session.
  Timer? _pendingSeekTimeout;

  void _clearPendingSeek() {
    _pendingSeekTarget = null;
    _pendingSeekTimeout?.cancel();
    _pendingSeekTimeout = null;
  }

  @override
  Future<void> open({
    required String url,
    required Map<String, String> httpHeaders,
    bool autoPlay = false,
  }) async {
    // Headers matter here for the same reason they do on the other
    // backends: panels commonly gate streams on a recognized player
    // User-Agent (see kIptvUserAgent).
    _playbackStartedSinceOpen = false;
    _clearPendingSeek();
    await _player.open(Media(url, httpHeaders: httpHeaders), play: autoPlay);
    await _makeStreamSeekable();
  }


  /// Tells libmpv to seek in streams it has decided are not seekable.
  ///
  /// Xtream VOD is plain HTTP and panels frequently answer without
  /// `Accept-Ranges`, or with chunked transfer encoding. mpv reads that as an
  /// unseekable stream, and an absolute seek on one of those does not fail —
  /// it lands at the end of what mpv currently holds, which to the viewer
  /// looks like jumping from 45:23 straight to the end of the episode. The
  /// same thing happens to the resume-seek when a part-watched episode is
  /// opened from history, so the video ends the instant it starts.
  ///
  /// `force-seekable` makes mpv issue the byte-range request anyway, which is
  /// what VLC does unprompted — hence the bug never appeared on iOS or
  /// Android. `reconnect` lets the HTTP connection be re-established when a
  /// seek forces mpv to re-request the file at a new offset.
  ///
  /// media_kit sets neither by default, so both go on after every open.
  /// Failures are swallowed deliberately: a stream that cannot honour them
  /// should still play, just without reliable seeking.
  Future<void> _makeStreamSeekable() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    try {
      await platform.setProperty('force-seekable', 'yes');
      await platform.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
      );
    } catch (_) {
      // Property unsupported by this libmpv build — playback still works.
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  /// Seeks, and blocks completion until playback settles at [position].
  ///
  /// libmpv reports end-of-file while it services a seek, before it reports
  /// the new position. Forwarded as-is that reads as "the video finished" no
  /// matter where the user actually jumped to, which is why scrubbing used
  /// to throw playback to the end of the episode.
  @override
  Future<void> seek(Duration position) {
    _pendingSeekTarget = position;
    _pendingSeekTimeout?.cancel();
    _pendingSeekTimeout = Timer(const Duration(seconds: 10), _clearPendingSeek);
    return _player.seek(position);
  }

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    await _positionWatch?.cancel();
    _positionWatch = null;
    _clearPendingSeek();
    await _player.dispose();
  }

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

  /// Only fires for a genuine end of the *current* media.
  ///
  /// libmpv's raw completion flag is not safe to forward as-is. It still
  /// holds the previous item's value while the next one loads, and media_kit
  /// replays that value to a new subscriber — so opening episode 3 straight
  /// after episode 2 finished delivers a `true` before episode 3 has played
  /// a frame. PlayerScreen reads that as "this episode ended" and advances
  /// again, which is why resuming a part-watched episode from history used
  /// to start the one after it.
  ///
  /// Two conditions have to hold. The media must have reported a position
  /// away from its own end since [open] (so state belongs to this item, not
  /// the last one), and the current position must actually be at the end.
  /// The other two backends emit completion only on real EOF, so this
  /// filtering is deliberately local to libmpv rather than in PlayerScreen.
  @override
  Stream<bool> get completedStream =>
      _player.stream.completed.where(_isGenuineCompletion);

  bool _isGenuineCompletion(bool completed) {
    if (!completed || !_playbackStartedSinceOpen || _pendingSeekTarget != null) {
      return false;
    }
    final duration = _player.state.duration;
    if (duration <= Duration.zero) {
      return false;
    }
    return duration - _player.state.position <= _endTolerance;
  }

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
