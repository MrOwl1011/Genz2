// Minimal native VLCKit platform view for iOS.
//
// This bypasses the flutter_vlc_player plugin's Dart-side player wrapper
// entirely and talks to MobileVLCKit directly. The command surface and
// event shape are intentionally small and mirror what NativeVlcKitBackend
// (lib/services/native_vlc_kit_backend.dart) expects.
//
// Reference for correct VLCMediaPlayer/VLCMedia usage patterns:
// https://github.com/solid-software/flutter_vlc_player (ios/Classes/VlcViewController.swift)
// In particular: VLCMediaPlayer accepts play()/pause()/seek calls immediately
// after `media` is assigned — no native-side readiness gate is needed here,
// unlike the Dart-side flutter_vlc_player wrapper which added its own
// "uninitialized controller" guard.

import Flutter
import Foundation
import MobileVLCKit
import UIKit

class NativeVlcPlayerView: NSObject, FlutterPlatformView {
  private let hostedView: UIView
  private let vlcMediaPlayer: VLCMediaPlayer
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    self.hostedView = UIView(frame: frame)
    self.hostedView.backgroundColor = .black
    self.vlcMediaPlayer = VLCMediaPlayer()
    self.methodChannel = FlutterMethodChannel(
      name: "native_vlc_player_channel_\(viewId)",
      binaryMessenger: messenger
    )
    self.eventChannel = FlutterEventChannel(
      name: "native_vlc_player_events_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    self.vlcMediaPlayer.drawable = self.hostedView
    self.vlcMediaPlayer.delegate = self
    self.eventChannel.setStreamHandler(self)
    self.methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func view() -> UIView {
    return hostedView
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "open":
      guard let urlString = args?["url"] as? String, let url = URL(string: urlString) else {
        result(FlutterError(code: "bad_args", message: "Missing/invalid url", details: nil))
        return
      }
      NSLog("[NativeVlcPlayerView] open: \(urlString)")
      let media = VLCMedia(url: url)
      if let userAgent = args?["userAgent"] as? String, !userAgent.isEmpty {
        media.addOption("--http-user-agent=\(userAgent)")
      }
      media.addOption("--network-caching=3000")
      vlcMediaPlayer.media = media
      // Mirrors flutter_vlc_player's own reference implementation: play()
      // must be called right after assigning media for VLCKit to actually
      // start loading it, then immediately stop again if the caller didn't
      // ask for autoplay. This is a real VLCKit requirement, not a bug.
      let autoPlay = (args?["autoPlay"] as? Bool) ?? false
      vlcMediaPlayer.play()
      if !autoPlay {
        vlcMediaPlayer.stop()
      }
      result(nil)

    case "play":
      vlcMediaPlayer.play()
      result(nil)

    case "pause":
      vlcMediaPlayer.pause()
      result(nil)

    case "stop":
      vlcMediaPlayer.stop()
      result(nil)

    case "seek":
      guard let ms = args?["positionMs"] as? Int else {
        result(FlutterError(code: "bad_args", message: "Missing positionMs", details: nil))
        return
      }
      vlcMediaPlayer.time = VLCTime(number: NSNumber(value: ms))
      result(nil)

    case "setRate":
      guard let rate = args?["rate"] as? Double else {
        result(FlutterError(code: "bad_args", message: "Missing rate", details: nil))
        return
      }
      vlcMediaPlayer.rate = Float(rate)
      result(nil)

    case "dispose":
      NSLog("[NativeVlcPlayerView] dispose")
      vlcMediaPlayer.stop()
      vlcMediaPlayer.delegate = nil
      eventSink = nil
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func stateString(_ state: VLCMediaPlayerState) -> String {
    switch state {
    case .opening: return "opening"
    case .buffering: return "buffering"
    case .playing: return "playing"
    case .paused: return "paused"
    case .stopped: return "stopped"
    case .ended: return "ended"
    case .error: return "error"
    case .esAdded: return "esAdded"
    @unknown default: return "unknown"
    }
  }

  private func emitState(eventName: String) {
    guard let eventSink = eventSink else { return }
    let position = vlcMediaPlayer.time.value?.intValue ?? 0
    let duration = vlcMediaPlayer.media?.length.value?.intValue ?? 0
    let width = Int(vlcMediaPlayer.videoSize.width)
    let height = Int(vlcMediaPlayer.videoSize.height)

    eventSink([
      "event": eventName,
      "state": stateString(vlcMediaPlayer.state),
      "isPlaying": vlcMediaPlayer.isPlaying,
      "positionMs": position,
      "durationMs": duration,
      "width": width,
      "height": height,
    ])
  }
}

extension NativeVlcPlayerView: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}

extension NativeVlcPlayerView: VLCMediaPlayerDelegate {
  func mediaPlayerStateChanged(_ aNotification: Notification) {
    NSLog("[NativeVlcPlayerView] state -> \(stateString(vlcMediaPlayer.state))")
    emitState(eventName: "stateChanged")
  }

  func mediaPlayerTimeChanged(_ aNotification: Notification) {
    emitState(eventName: "timeChanged")
  }
}
