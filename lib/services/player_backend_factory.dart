import 'media_kit_backend.dart';
import 'player_backend.dart';
import 'player_engine.dart';
import 'vlc_backend.dart';

/// Constructs the concrete [PlayerBackend] for [engine].
PlayerBackend createPlayerBackend(PlayerEngine engine) {
  switch (engine) {
    case PlayerEngine.vlc:
      return VlcBackend();
    case PlayerEngine.mediaKit:
      return MediaKitBackend();
  }
}
