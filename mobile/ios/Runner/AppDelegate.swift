import CoreHaptics
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let haptics = Haptics()

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
    // The game's rumble.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Haptics") {
      FlutterMethodChannel(name: "org.anyps5.remote/haptics", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { [weak self] call, result in
          guard call.method == "set", let arguments = call.arguments as? [String: Any] else { return result(FlutterMethodNotImplemented) }
          self?.haptics.set(strength: arguments["strength"] as? Int ?? 0, sharpness: arguments["sharpness"] as? Double ?? 0.5)
          result(nil)
        }
    }
  }
}

/// The game's rumble on the iPhone: one continuous haptic that loops while the game asks for
/// one, its intensity and sharpness changed as the game's motors change.
final class Haptics {
  private var engine: CHHapticEngine?
  private var player: CHHapticAdvancedPatternPlayer?

  func set(strength: Int, sharpness: Double) {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
    if strength <= 0 {
      try? player?.stop(atTime: CHHapticTimeImmediate)
      player = nil
      return
    }
    do {
      if player == nil { player = try makePlayer() }
      try player?.sendParameters([
        CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Float(min(strength, 255)) / 255, relativeTime: 0),
        CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: Float(sharpness) - 0.5, relativeTime: 0),
      ], atTime: CHHapticTimeImmediate)
    } catch {
      player = nil
    }
  }

  private func makePlayer() throws -> CHHapticAdvancedPatternPlayer {
    if engine == nil {
      let made = try CHHapticEngine()
      made.isAutoShutdownEnabled = true
      made.resetHandler = { [weak self] in self?.player = nil }
      made.stoppedHandler = { [weak self] _ in self?.player = nil }
      engine = made
    }
    try engine?.start()
    let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
      CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
      CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
    ], relativeTime: 0, duration: 30)
    let made = try engine!.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
    made.loopEnabled = true
    try made.start(atTime: CHHapticTimeImmediate)
    return made
  }
}
