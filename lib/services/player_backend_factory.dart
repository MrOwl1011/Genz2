import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'exoplayer_backend.dart';
import 'native_vlc_kit_backend.dart';
import 'player_backend.dart';

/// Constructs the [PlayerBackend] for the current platform.
///
/// On iOS it's a hand-written native backend talking directly to MobileVLCKit
/// ([NativeVlcKitBackend]). On Android it uses ExoPlayer via the
/// `video_player` package ([ExoPlayerBackend]).
PlayerBackend createPlayerBackend() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return NativeVlcKitBackend();
  }
  return ExoPlayerBackend();
}
