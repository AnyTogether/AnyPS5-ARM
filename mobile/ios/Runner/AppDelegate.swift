import AVFoundation
import CoreHaptics
import Flutter
import UIKit
import VideoToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let haptics = Haptics()
  private var stream: StreamPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The game's rumble keeps going while the party's voice records.
    try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The phone's name, shown on the Mac as the phone that connected.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceName") {
      FlutterMethodChannel(name: "org.anyps5.remote/device", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          switch call.method {
          case "name": result(UIDevice.current.name)
          case "rotation":
            // Landscape right is the home side on the right: the phone's top is to the left.
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            result(scene?.interfaceOrientation == .landscapeLeft ? "topRight" : "topLeft")
          default: result(FlutterMethodNotImplemented)
          }
        }
    }
    // Remote Play's picture and sound.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Stream") {
      let channel = FlutterMethodChannel(name: "org.anyps5.remote/stream", binaryMessenger: registrar.messenger())
      let player = StreamPlayer(textures: registrar.textures(), channel: channel)
      stream = player
      channel.setMethodCallHandler { call, result in
        let arguments = call.arguments as? [String: Any]
        switch call.method {
        case "open": result(player.open())
        case "frame":
          if let data = arguments?["data"] as? FlutterStandardTypedData { player.frame(data.data) }
          result(nil)
        case "sound":
          if let data = arguments?["data"] as? FlutterStandardTypedData { player.sound(data.data) }
          result(nil)
        case "close":
          player.close()
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
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

/// Remote Play on the iPhone: the launcher's H.264 frames decoded by VideoToolbox into a
/// Flutter texture, each shown as soon as it is decoded, and its 16-bit stereo sound played by
/// AVAudioEngine, never more than 100 ms behind.
final class StreamPlayer: NSObject, FlutterTexture {
  private let textures: FlutterTextureRegistry
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "org.anyps5.stream", qos: .userInteractive)
  private let lock = NSLock()
  private var latest: CVPixelBuffer?
  private var textureID: Int64?
  private var session: VTDecompressionSession?
  private var format: CMVideoFormatDescription?
  private var size = CGSize.zero
  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
  private let queuedFrames = Counter()

  init(textures: FlutterTextureRegistry, channel: FlutterMethodChannel) {
    self.textures = textures
    self.channel = channel
    super.init()
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: audioFormat)
  }

  func open() -> Int64 {
    close()
    let id = textures.register(self)
    textureID = id
    return id
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    return latest.map { Unmanaged.passRetained($0) }
  }

  func frame(_ data: Data) {
    queue.async { self.decode(data) }
  }

  /// Start codes split the frame into units: parameter sets make the format (and a new decoder
  /// when it changes), the rest go to the decoder with a length before each.
  private func decode(_ data: Data) {
    var parameterSets: [Data] = []
    var slices = Data()
    for unit in StreamPlayer.units(data) {
      guard let header = unit.first else { continue }
      switch header & 0x1F {
      case 7, 8: parameterSets.append(unit)
      default:
        var length = UInt32(unit.count).bigEndian
        slices.append(Data(bytes: &length, count: 4))
        slices.append(unit)
      }
    }
    if parameterSets.count >= 2, let made = StreamPlayer.format(parameterSets) {
      if format == nil || !CMFormatDescriptionEqual(made, otherFormatDescription: format!) {
        format = made
        makeSession(made)
      }
    }
    guard let session, let format, !slices.isEmpty else { return }
    var block: CMBlockBuffer?
    let count = slices.count
    guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: count,
                                             flags: 0, blockBufferOut: &block) == noErr, let block else { return }
    slices.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: count) }
    var sample: CMSampleBuffer?
    var sizes = [count]
    guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                    sampleSizeEntryCount: 1, sampleSizeArray: &sizes, sampleBufferOut: &sample) == noErr, let sample else { return }
    VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { [weak self] status, _, image, _, _ in
      guard let self, status == noErr, let image else { return }
      self.lock.lock()
      self.latest = image
      self.lock.unlock()
      DispatchQueue.main.async {
        if let id = self.textureID { self.textures.textureFrameAvailable(id) }
      }
    }
  }

  private func makeSession(_ format: CMVideoFormatDescription) {
    if let session { VTDecompressionSessionInvalidate(session) }
    session = nil
    let attributes: [CFString: Any] = [
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
      kCVPixelBufferMetalCompatibilityKey: true,
    ]
    var made: VTDecompressionSession?
    guard VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
                                       outputCallback: nil, decompressionSessionOut: &made) == noErr, let made else { return }
    VTSessionSetProperty(made, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    session = made
    let dimensions = CMVideoFormatDescriptionGetDimensions(format)
    let shown = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
    if shown != size {
      size = shown
      DispatchQueue.main.async { self.channel.invokeMethod("size", arguments: [Int(shown.width), Int(shown.height)]) }
    }
  }

  static func format(_ sets: [Data]) -> CMVideoFormatDescription? {
    let sps = sets.first { ($0.first ?? 0) & 0x1F == 7 }, pps = sets.first { ($0.first ?? 0) & 0x1F == 8 }
    guard let sps, let pps else { return nil }
    var made: CMVideoFormatDescription?
    let status = sps.withUnsafeBytes { spsBytes in
      pps.withUnsafeBytes { ppsBytes in
        let pointers = [spsBytes.bindMemory(to: UInt8.self).baseAddress!, ppsBytes.bindMemory(to: UInt8.self).baseAddress!]
        let sizes = [sps.count, pps.count]
        return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers, parameterSetSizes: sizes,
                                                                   nalUnitHeaderLength: 4, formatDescriptionOut: &made)
      }
    }
    return status == noErr ? made : nil
  }

  /// The units between start codes (00 00 01 or 00 00 00 01).
  static func units(_ data: Data) -> [Data] {
    let bytes = [UInt8](data)
    var starts: [(Int, Int)] = []
    var index = 0
    while index + 3 <= bytes.count {
      if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
        starts.append((index, index + 3))
        index += 3
      } else {
        index += 1
      }
    }
    return starts.enumerated().map { number, start in
      var end = number + 1 < starts.count ? starts[number + 1].0 : bytes.count
      // The zero before a four-byte start code belongs to it.
      if number + 1 < starts.count, end > start.1, bytes[end - 1] == 0 { end -= 1 }
      return Data(bytes[start.1 ..< max(start.1, end)])
    }
  }

  func sound(_ data: Data) {
    queue.async {
      let frames = data.count / 4
      // More than 100 ms waiting to be played: this sound is dropped to catch up.
      guard frames > 0, self.queuedFrames.value < 4800, let buffer = AVAudioPCMBuffer(pcmFormat: self.audioFormat, frameCapacity: AVAudioFrameCount(frames)),
            let channels = buffer.floatChannelData else { return }
      buffer.frameLength = AVAudioFrameCount(frames)
      data.withUnsafeBytes { raw in
        let samples = raw.bindMemory(to: Int16.self)
        for frame in 0 ..< frames {
          channels[0][frame] = Float(Int16(littleEndian: samples[frame * 2])) / 32768
          channels[1][frame] = Float(Int16(littleEndian: samples[frame * 2 + 1])) / 32768
        }
      }
      if !self.engine.isRunning {
        // In a party's voice the session records too: the game's sound joins it as it is.
        if AVAudioSession.sharedInstance().category != .playAndRecord {
          try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? AVAudioSession.sharedInstance().setPreferredIOBufferDuration(0.005)
        try? AVAudioSession.sharedInstance().setActive(true)
        try? self.engine.start()
        self.node.play()
      }
      let queued = self.queuedFrames
      queued.add(frames)
      self.node.scheduleBuffer(buffer) { queued.add(-frames) }
    }
  }

  func close() {
    queue.sync {
      if let session { VTDecompressionSessionInvalidate(session) }
      session = nil
      format = nil
      size = .zero
      node.stop()
      engine.stop()
      queuedFrames.reset()
    }
    lock.lock()
    latest = nil
    lock.unlock()
    if let id = textureID { textures.unregisterTexture(id) }
    textureID = nil
  }
}

/// Sound frames waiting to be played, counted from two threads.
final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func add(_ amount: Int) {
    lock.lock()
    count += amount
    lock.unlock()
  }

  func reset() {
    lock.lock()
    count = 0
    lock.unlock()
  }
}
