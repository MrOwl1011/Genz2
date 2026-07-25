import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Identifies a selectable video playback engine.
enum PlayerEngine { mediaKit, vlc, nativePlayer }

/// Every engine the app knows how to build, in the order they should be
/// shown to the user. Add a new backend + a case here to offer more engines.
const List<PlayerEngine> kAllPlayerEngines = [
  PlayerEngine.mediaKit,
  PlayerEngine.vlc,
  PlayerEngine.nativePlayer,
];

extension PlayerEngineX on PlayerEngine {
  String get id {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'media_kit';
      case PlayerEngine.vlc:
        return 'vlc';
      case PlayerEngine.nativePlayer:
        return 'native_player';
    }
  }

  String get label {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'Media Kit';
      case PlayerEngine.vlc:
        return 'VLC';
      case PlayerEngine.nativePlayer:
        return 'Native Player';
    }
  }

  String get labelAr {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'ميديا كيت';
      case PlayerEngine.vlc:
        return 'في إل سي';
      case PlayerEngine.nativePlayer:
        return 'المشغل الأصلي';
    }
  }

  String get description {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'Fast libmpv engine. Recommended on Android, Windows, macOS and Linux.';
      case PlayerEngine.vlc:
        return 'VLC-powered engine. Recommended on iOS and for streams other engines struggle with.';
      case PlayerEngine.nativePlayer:
        return 'AVPlayer on iOS/macOS, ExoPlayer on Android. Excellent HLS support; '
            'may not play raw MPEG-TS streams some providers use.';
    }
  }

  String get descriptionAr {
    switch (this) {
      case PlayerEngine.mediaKit:
        return 'محرك سريع (libmpv). مناسب لأندرويد وويندوز وماك ولينكس.';
      case PlayerEngine.vlc:
        return 'محرك مدعوم من VLC. مستحسن لنظام iOS وللبثوث الصعبة.';
      case PlayerEngine.nativePlayer:
        return 'AVPlayer على iOS/macOS، وExoPlayer على أندرويد. دعم ممتاز لـ HLS، وقد لا يعمل مع بعض بثوث MPEG-TS.';
    }
  }

  /// Whether this engine can actually run on the platform the app is on.
  bool get isSupported {
    switch (this) {
      case PlayerEngine.mediaKit:
        // Ships everywhere except web.
        return !kIsWeb;
      case PlayerEngine.vlc:
        if (kIsWeb) return false;
        return defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android;
      case PlayerEngine.nativePlayer:
        // video_player officially supports Android, iOS, macOS and web.
        if (kIsWeb) return true;
        return defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.macOS;
    }
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
