import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The phone's name, shown on the Mac as the phone that connected.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceName") {
      FlutterMethodChannel(name: "org.anyps5.remote/device", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          result(call.method == "name" ? UIDevice.current.name : FlutterMethodNotImplemented)
        }
    }
  }
}
