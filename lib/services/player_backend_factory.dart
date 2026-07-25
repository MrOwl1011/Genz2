import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'media_kit_backend.dart';
import 'native_vlc_kit_backend.dart';
import 'player_backend.dart';
import 'player_engine.dart';
import 'video_player_backend.dart';
import 'vlc_backend.dart';

/// Constructs the concrete [PlayerBackend] for [engine].
///
/// [PlayerEngine.vlc] is platform-conditional: iOS gets a hand-written
/// native backend talking directly to MobileVLCKit
/// ([NativeVlcKitBackend]), bypassing the flutter_vlc_player plugin's Dart
/// wrapper entirely. Every other platform (Android) keeps using
/// [VlcBackend] (flutter_vlc_player) unchanged.
PlayerBackend createPlayerBackend(PlayerEngine engine) {
  switch (engine) {
    case PlayerEngine.vlc:
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        return NativeVlcKitBackend();
      }
      return VlcBackend();
    case PlayerEngine.mediaKit:
      return MediaKitBackend();
    case PlayerEngine.nativePlayer:
      return VideoPlayerBackend();
  }
}
