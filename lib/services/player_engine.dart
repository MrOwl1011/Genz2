import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Identifies a selectable video playback engine.
enum PlayerEngine { mediaKit, vlc }

/// Every engine the app knows how to build, in the order they should be
/// shown to the user. Add a new backend + a case here to offer more engines.
const List<PlayerEngine> kAllPlayerEngines = [
  PlayerEngine.mediaKit,
  PlayerEngine.vlc,
];

extension PlayerEngineX on PlayerEngine {
  String get id {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'media_kit';
      case PlayerEngine.vlc:
        return 'vlc';
    }
  }

  String get label {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'Media Kit';
      case PlayerEngine.vlc:
        return 'VLC';
    }
  }

  String get labelAr {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'ميديا كيت';
      case PlayerEngine.vlc:
        return 'في إل سي';
    }
  }

  String get description {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'Fast libmpv engine. Recommended on Android, Windows, macOS and Linux.';
      case PlayerEngine.vlc:
        return 'VLC-powered engine. Recommended on iOS and for streams other engines struggle with.';
    }
  }

  String get descriptionAr {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'محرك سريع (libmpv). مناسب لأندرويد وويندوز وماك ولينكس.';
      case PlayerEngine.vlc:
        return 'محرك مدعوم من VLC. مستحسن لنظام iOS وللبثوث الصعبة.';
    }
  }

  /// Whether this engine can actually run on the platform the app is on.
  bool get isSupported {
    if (kIsWeb) return this == PlayerEngine.mediaKit;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      return true;
    }
    // Windows, macOS, Linux: only the libmpv-backed engine ships there.
    return this == PlayerEngine.mediaKit;
  }
}

/// Engines that can actually run on the current platform, in display order.
List<PlayerEngine> get availablePlayerEngines =>
    kAllPlayerEngines.where((e) => e.isSupported).toList(growable: false);

/// The engine used until the user picks one explicitly.
/// iOS defaults to VLC; every other platform keeps using Media Kit.
PlayerEngine get defaultPlayerEngine {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return PlayerEngine.vlc;
  }
  return PlayerEngine.mediaKit;
}

/// Resolves a persisted engine id back to a [PlayerEngine], falling back to
/// [defaultPlayerEngine] if the id is unknown or unsupported on this device
/// (e.g. a VLC choice synced from a phone onto a desktop build).
PlayerEngine playerEngineFromId(String? id) {
  for (final engine in kAllPlayerEngines) {
    if (engine.id == id) {
      return engine.isSupported ? engine : defaultPlayerEngine;
    }
  }
  return defaultPlayerEngine;
}
