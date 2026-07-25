import Flutter
import UIKit

public class NativeVlcPlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let factory = NativeVlcPlayerViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "native_vlc_player_view")
  }
}
