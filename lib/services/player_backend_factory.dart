import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'exoplayer_backend.dart';
import 'media_kit_backend.dart';
import 'native_vlc_kit_backend.dart';
import 'player_backend.dart';

/// Constructs the [PlayerBackend] for the current platform.
///
/// iOS uses a hand-written native backend talking directly to MobileVLCKit
/// ([NativeVlcKitBackend]). Desktop uses libmpv via `media_kit`
/// ([MediaKitBackend]) — `video_player` has no Windows implementation, so
/// the Android path would fail there at runtime. Everything else uses
/// ExoPlayer via the `video_player` package ([ExoPlayerBackend]).
PlayerBackend createPlayerBackend() {
  if (kIsWeb) return ExoPlayerBackend();
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return NativeVlcKitBackend();
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return MediaKitBackend();
    default:
      return ExoPlayerBackend();
  }
}
