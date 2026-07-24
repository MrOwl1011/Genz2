import 'package:flutter/widgets.dart';

/// A unified surface over a concrete video engine (Media Kit, VLC, ...) so
/// [PlayerScreen] can drive playback without knowing which engine is active.
///
/// Every stream getter must return the *same* broadcast stream for the
/// lifetime of the backend instance, valid immediately after construction —
/// callers are expected to subscribe before [open] resolves.
abstract class PlayerBackend {
  /// Starts loading [url]. Does not start playback unless [autoPlay] is
  /// true; callers that need to seek before the first frame renders should
  /// keep this false and call [play] once they are ready.
  Future<void> open({
    required String url,
    required Map<String, String> httpHeaders,
    bool autoPlay = false,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> stop();
  Future<void> dispose();

  /// Current values, polled synchronously by the resume-seek routine.
  Duration get position;
  Duration get duration;
  bool get isPlaying;

  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get bufferingStream;
  Stream<String> get errorStream;
  Stream<bool> get completedStream;
  Stream<int?> get widthStream;
  Stream<int?> get heightStream;

  /// The raw video surface widget. Callers wrap it in their own sizing /
  /// aspect-ratio widgets and should pass the aspect ratio they intend to
  /// present it at so engines that need it (e.g. VLC) can match it exactly.
  Widget buildVideoWidget({Key? key, required double aspectRatio});
}
