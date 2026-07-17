# GenZ IPTV - Premium Media Player 📺

GenZ is a high-performance, feature-rich IPTV and media streaming application built with Flutter. Designed with a focus on premium UX/UI, the application supports Live TV, VOD (Movies & Series), and handles a massive variety of video formats through a highly customized player interface.

## 🚀 Recent Updates & Major Fixes

### 1. Complete `media_kit` Engine Migration (Replacing `video_player` / `chewie`)
The core video rendering engine has been completely overhauled. The app no longer relies on the native ExoPlayer (Android) or AVPlayer (iOS), and instead utilizes `media_kit` (powered by `libmpv` and FFmpeg).

* **Fixed iOS Playback Errors:** Completely eliminated the infamous iOS `PlatformException(VideoError)... OSStatus error -12847` by bypassing AVFoundation's strict codec limitations.
* **Broad Format Support:** Native support for MKV, TS, HEVC/H.265, MP4, and complex HLS (`.m3u8`) streams on both Android and iOS.
* **Performance:** Implemented robust stream subscriptions to handle buffering, playing, and seeking states without unnecessarily rebuilding the entire widget tree.

### 2. RTL (Right-to-Left) Player Control Fix
* **The Problem:** Changing the app language to Arabic (RTL) caused the entire media player UI (seek bar, gesture zones, control buttons) to mirror itself.
* **The Solution:** The media controls (timeline, sliders, double-tap zones) are now strictly enforced as Left-to-Right (LTR) to match standard media player UX patterns. However, text shaping, localized strings, and menus (like the Settings Sheet) retain full RTL support and format perfectly.

### 3. iPad Compatibility & Stability Fixes
* Added the `UIRequiresFullScreen` requirement to the iOS `Info.plist`. 
* This prevents strict Split-Screen multitasking constraints from crashing or rejecting the application on iPadOS, ensuring the player stretches beautifully across all iPad screens (like the iPad Mini) in immersive full-screen mode.

### 4. Build Configuration Updates
* **Android:** Bumped `minSdk` to 21 to support modern C++ native libraries used by the new player.
* **iOS:** Added `NSAppTransportSecurity` for unencrypted HTTP streams and enabled `audio` in `UIBackgroundModes` for continued playback.

---

## ✨ Core Features

* **Live TV & VOD:** Dedicated screens and playback modes for live streaming and on-demand content.
* **Mini-Player:** Seamless mini-player integration within the Channels screen.
* **Advanced Gestures:** Double-tap screen edges to seek (forward/rewind).
* **Vertical Sliders:** On-screen intuitive swipe gestures to control Brightness (left side) and Volume (right side).
* **Multi-Track Support:** Dynamic selection of Audio tracks and Subtitles embedded in the stream.
* **Screen Lock:** UI lock button to prevent accidental touches during immersive viewing.
* **Picture-in-Picture (PiP):** (Where supported by the device) for multi-tasking.

---

## 🛠️ Tech Stack & Dependencies

* **Framework:** Flutter
* **Video Engine:** `media_kit`, `media_kit_video`, `media_kit_libs_video`
* **Styling:** Custom UI with `google_fonts`
* **Hardware Interfacing:** `screen_brightness`, `volume_controller`

## ⚙️ Getting Started

### Prerequisites
* Flutter SDK (Latest Stable)
* Android Studio (with NDK installed, as `media_kit` compiles C++ libraries)
* Xcode (for iOS builds)

### Build Instructions

**Android:**
```bash
flutter clean
flutter pub get
flutter build apk --release
```

**iOS:**
```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release
```

*(Note: If sideloading to an iPad via Sideloadly, ensure the IPA is built targeting the Universal device family).*
