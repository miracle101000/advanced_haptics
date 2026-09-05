import Flutter
import UIKit
import CoreHaptics

/// iOS implementation of the `advanced_haptics` plugin.
///
/// Devices with Core Haptics (iPhone 8 and newer) drive a single shared
/// `CHHapticAdvancedPatternPlayer`, so starting a new pattern always replaces
/// the previous one and the player controls have one obvious target. Devices
/// without Core Haptics (iPads, iPhone 7 and older) fall back to
/// `UIFeedbackGenerator`, so callers never have to special-case hardware.
///
/// All state is confined to the main thread: Flutter delivers method calls
/// there and the engine callbacks are re-dispatched onto it.
public class AdvancedHapticsPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.example/advanced_haptics"
  private static let maxAmplitude = 255.0
  /// "On" segments shorter than this are rendered as a transient (tap) event,
  /// which is far more perceptible than a very short continuous event.
  private static let transientThreshold: TimeInterval = 0.04
  private static let waveformSharpness: Float = 0.8
  /// Shortest loop the timer-driven fallback is willing to run.
  private static let minimumFallbackLoop: TimeInterval = 0.02

  private let supportsCoreHaptics: Bool
  private var engine: CHHapticEngine?
  private var advancedPlayer: CHHapticAdvancedPatternPlayer?
  private var isEngineRunning = false

  /// Fallback playback (no Core Haptics) is driven by dispatch timers. Bumping
  /// this generation invalidates every timer that is still pending.
  private var fallbackGeneration = 0
  private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

  private enum EngineStateError: Error {
    case unavailable
    case restartFailed(Error)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = AdvancedHapticsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  override init() {
    supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    super.init()
    if supportsCoreHaptics {
      setupHapticEngine()
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    fallbackGeneration += 1
    if let player = advancedPlayer {
      _ = try? player.cancel()
    }
    advancedPlayer = nil
    engine?.stop(completionHandler: nil)
    engine = nil
    isEngineRunning = false
  }

  // MARK: - Engine lifecycle

  private func setupHapticEngine() {
    guard supportsCoreHaptics else { return }
    do {
      let newEngine = try CHHapticEngine()

      newEngine.resetHandler = { [weak self] in
        DispatchQueue.main.async {
          guard let self = self, self.engine === newEngine else { return }
          // Players created before a reset are invalid.
          self.advancedPlayer = nil
          do {
            try newEngine.start()
            self.isEngineRunning = true
          } catch {
            self.log("Failed to restart the haptic engine after a reset: \(error.localizedDescription)")
            self.isEngineRunning = false
          }
        }
      }

      newEngine.stoppedHandler = { [weak self] reason in
        DispatchQueue.main.async {
          guard let self = self, self.engine === newEngine else { return }
          self.log("Haptic engine stopped (reason \(reason.rawValue)).")
          self.advancedPlayer = nil
          self.isEngineRunning = false
        }
      }

      try newEngine.start()
      engine = newEngine
      isEngineRunning = true
    } catch {
      log("Could not create the haptic engine: \(error.localizedDescription)")
      engine = nil
      isEngineRunning = false
    }
  }

  /// Returns a running engine, (re)starting or re-creating it when needed.
  /// The engine stops whenever the app is suspended, so this runs before
  /// every playback.
  private func ensureHapticEngineReady() throws -> CHHapticEngine {
    guard supportsCoreHaptics else { throw EngineStateError.unavailable }
    if engine == nil {
      setupHapticEngine()
    }
    guard let engine = engine else { throw EngineStateError.unavailable }
    if isEngineRunning {
      return engine
    }
    do {
      try engine.start()
      isEngineRunning = true
      return engine
    } catch {
      log("Failed to start the haptic engine (\(error.localizedDescription)); re-creating it.")
      self.engine = nil
      isEngineRunning = false
      setupHapticEngine()
      guard let restarted = self.engine, isEngineRunning else {
        throw EngineStateError.restartFailed(error)
      }
      return restarted
    }
  }

  // MARK: - Method channel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "hasCustomHapticsSupport":
      result(supportsCoreHaptics)

    case "playWaveform":
      handlePlayWaveform(args, result)

    case "playAhap":
      handlePlayAhap(args, result)

    case "success":
      handleSuccess(result)

    case "playPredefined":
      // Android-only effect IDs; documented as ignored on iOS.
      result(nil)

    case "pause", "resume", "seek":
      handlePlayerControl(call.method, args, result)

    case "stop":
      stopPlayback(delay: doubleArg(args, "atTime"), result: result)

    case "cancel":
      cancelPlayback(result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handlePlayWaveform(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let timings = numberArray(args["timings"]),
          let amplitudes = numberArray(args["amplitudes"]) else {
      result(FlutterError(code: "INVALID_ARGS",
                          message: "'timings' and 'amplitudes' must be lists of numbers.",
                          details: nil))
      return
    }
    guard !timings.isEmpty, timings.count == amplitudes.count else {
      result(FlutterError(code: "INVALID_ARGS",
                          message: "'timings' and 'amplitudes' must be non-empty and of equal length.",
                          details: nil))
      return
    }
    let repeatIndex = intArg(args, "repeat", default: -1)
    guard repeatIndex == -1 || (0..<timings.count).contains(repeatIndex) else {
      result(FlutterError(code: "INVALID_ARGS",
                          message: "'repeat' must be -1 or an index into 'timings' (got \(repeatIndex)).",
                          details: nil))
      return
    }
    let delay = doubleArg(args, "atTime")

    // Convert to seconds / 0...1. Dart validates the ranges; clamp anyway so a
    // stray value can never produce an invalid Core Haptics parameter.
    let durations = timings.map { max(0, $0) / 1000.0 }
    let intensities = amplitudes.map {
      min(max($0, 0), AdvancedHapticsPlugin.maxAmplitude) / AdvancedHapticsPlugin.maxAmplitude
    }
    let totalDuration = durations.reduce(0, +)
    guard totalDuration > 0 else {
      // Nothing to play: succeed without touching the hardware.
      result(nil)
      return
    }

    guard supportsCoreHaptics else {
      playWaveformFallback(durations: durations, intensities: intensities,
                           repeatIndex: repeatIndex, delay: delay)
      result(nil)
      return
    }

    var events: [CHHapticEvent] = []
    var relativeTime: TimeInterval = 0
    for (duration, intensity) in zip(durations, intensities) {
      // A continuous event needs both an intensity and a positive duration,
      // otherwise Core Haptics rejects the pattern (error -4823).
      if intensity > 0 && duration > 0 {
        let parameters = [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: AdvancedHapticsPlugin.waveformSharpness),
        ]
        if duration < AdvancedHapticsPlugin.transientThreshold {
          events.append(CHHapticEvent(eventType: .hapticTransient, parameters: parameters,
                                      relativeTime: relativeTime))
        } else {
          events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: parameters,
                                      relativeTime: relativeTime, duration: duration))
        }
      }
      // Pauses and zero-amplitude segments still advance the timeline.
      relativeTime += duration
    }

    guard !events.isEmpty else {
      result(nil)
      return
    }

    do {
      let pattern = try CHHapticPattern(events: events, parameters: [])
      // Core Haptics loops the whole pattern; loopEnd must cover trailing
      // silence, otherwise the loop point is the end of the last event.
      play(pattern: pattern, delay: delay, loop: repeatIndex >= 0, loopEnd: totalDuration, result: result)
    } catch {
      result(FlutterError(code: "PATTERN_ERROR",
                          message: "Failed to create pattern from waveform data.",
                          details: error.localizedDescription))
    }
  }

  private func handlePlayAhap(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let path = args["path"] as? String, !path.isEmpty else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path' argument.", details: nil))
      return
    }
    let delay = doubleArg(args, "atTime")

    guard supportsCoreHaptics else {
      // Approximate with a strong double pulse, mirroring the Android fallback.
      playWaveformFallback(durations: [0, 0.1, 0.05, 0.1], intensities: [0, 1.0, 0, 0.6],
                           repeatIndex: -1, delay: delay)
      result(nil)
      return
    }

    guard let url = resolveAhapURL(path) else {
      result(FlutterError(code: "FILE_NOT_FOUND",
                          message: "AHAP file not found. Pass a Flutter asset path declared in pubspec.yaml or an absolute file path.",
                          details: path))
      return
    }

    do {
      let pattern = try loadPattern(from: url)
      play(pattern: pattern, delay: delay, loop: false, loopEnd: 0, result: result)
    } catch {
      result(FlutterError(code: "PATTERN_ERROR",
                          message: "Failed to create pattern from AHAP file.",
                          details: error.localizedDescription))
    }
  }

  private func handleSuccess(_ result: @escaping FlutterResult) {
    guard supportsCoreHaptics else {
      fallbackGeneration += 1
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      result(nil)
      return
    }
    do {
      let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
      let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
      let first = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
      let second = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.1)
      let pattern = try CHHapticPattern(events: [first, second], parameters: [])
      play(pattern: pattern, delay: 0, loop: false, loopEnd: 0, result: result)
    } catch {
      result(FlutterError(code: "PLAYBACK_ERROR",
                          message: "Failed to play success pattern.",
                          details: error.localizedDescription))
    }
  }

  private func handlePlayerControl(_ method: String, _ args: [String: Any], _ result: @escaping FlutterResult) {
    guard supportsCoreHaptics else {
      // There is no player to control in fallback mode; nothing to do.
      result(nil)
      return
    }
    guard let player = advancedPlayer, let engine = engine else {
      result(FlutterError(code: "PLAYER_NIL", message: "No haptic player is currently active.", details: nil))
      return
    }
    do {
      switch method {
      case "pause":
        try player.pause(atTime: absoluteTime(engine, delay: doubleArg(args, "atTime")))
      case "resume":
        try player.resume(atTime: absoluteTime(engine, delay: doubleArg(args, "atTime")))
      default:
        try player.seek(toOffset: doubleArg(args, "offset"))
      }
      result(nil)
    } catch {
      result(FlutterError(code: "PLAYER_CONTROL_ERROR",
                          message: "Failed to execute player command: \(method)",
                          details: error.localizedDescription))
    }
  }

  // MARK: - Playback

  private func play(pattern: CHHapticPattern, delay: TimeInterval, loop: Bool, loopEnd: TimeInterval,
                    result: @escaping FlutterResult) {
    fallbackGeneration += 1
    do {
      let engine = try ensureHapticEngineReady()

      // Best effort: a stale player (for example after an engine reset) must
      // never block new playback.
      if let previous = advancedPlayer {
        _ = try? previous.stop(atTime: CHHapticTimeImmediate)
      }
      advancedPlayer = nil

      let player = try engine.makeAdvancedPlayer(with: pattern)
      player.loopEnabled = loop
      if loop {
        player.loopEnd = loopEnd
      }
      player.completionHandler = { [weak self] _ in
        DispatchQueue.main.async {
          guard let self = self, let current = self.advancedPlayer,
                (current as AnyObject) === (player as AnyObject) else { return }
          self.advancedPlayer = nil
        }
      }
      try player.start(atTime: absoluteTime(engine, delay: delay))
      advancedPlayer = player
      result(nil)
    } catch {
      result(flutterError(for: error))
    }
  }

  private func stopPlayback(delay: TimeInterval, result: @escaping FlutterResult) {
    if delay > 0 {
      let generation = fallbackGeneration
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self = self, self.fallbackGeneration == generation else { return }
        self.fallbackGeneration += 1
      }
    } else {
      fallbackGeneration += 1
    }

    // Stopping when nothing is playing is a successful no-op.
    guard let player = advancedPlayer else {
      result(nil)
      return
    }
    do {
      if delay > 0, let engine = engine {
        try player.stop(atTime: absoluteTime(engine, delay: delay))
        // Keep the reference until the scheduled stop completes; the
        // completion handler releases it.
      } else {
        try player.stop(atTime: CHHapticTimeImmediate)
        advancedPlayer = nil
      }
    } catch {
      // A stop can only fail when the engine is no longer running, in which
      // case nothing is playing anyway.
      log("Ignoring stop failure: \(error.localizedDescription)")
      advancedPlayer = nil
    }
    result(nil)
  }

  private func cancelPlayback(result: @escaping FlutterResult) {
    fallbackGeneration += 1
    guard let player = advancedPlayer else {
      result(nil)
      return
    }
    advancedPlayer = nil
    do {
      try player.cancel()
    } catch {
      log("Ignoring cancel failure: \(error.localizedDescription)")
    }
    result(nil)
  }

  // MARK: - Fallback without Core Haptics

  private func playWaveformFallback(durations: [TimeInterval], intensities: [Double],
                                    repeatIndex: Int, delay: TimeInterval) {
    fallbackGeneration += 1
    var loopFrom = -1
    if repeatIndex >= 0 && repeatIndex < durations.count {
      let loopDuration = durations[repeatIndex...].reduce(0, +)
      if loopDuration >= AdvancedHapticsPlugin.minimumFallbackLoop {
        loopFrom = repeatIndex
      }
    }
    scheduleFallbackPass(durations, intensities, from: 0, loopFrom: loopFrom,
                         generation: fallbackGeneration, startAfter: max(0, delay))
  }

  private func scheduleFallbackPass(_ durations: [TimeInterval], _ intensities: [Double],
                                    from startIndex: Int, loopFrom: Int, generation: Int,
                                    startAfter: TimeInterval) {
    var offset = startAfter
    for index in startIndex..<durations.count {
      let duration = durations[index]
      let intensity = intensities[index]
      if intensity > 0 && duration > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + offset) { [weak self] in
          guard let self = self, self.fallbackGeneration == generation else { return }
          self.fireImpact(intensity: intensity)
        }
      }
      offset += duration
    }
    if loopFrom >= 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + offset) { [weak self] in
        guard let self = self, self.fallbackGeneration == generation else { return }
        self.scheduleFallbackPass(durations, intensities, from: loopFrom, loopFrom: loopFrom,
                                  generation: generation, startAfter: 0)
      }
    }
  }

  private func fireImpact(intensity: Double) {
    let style: UIImpactFeedbackGenerator.FeedbackStyle
    if intensity < 0.34 {
      style = .light
    } else if intensity < 0.67 {
      style = .medium
    } else {
      style = .heavy
    }
    let generator: UIImpactFeedbackGenerator
    if let cached = impactGenerators[style] {
      generator = cached
    } else {
      generator = UIImpactFeedbackGenerator(style: style)
      impactGenerators[style] = generator
    }
    generator.impactOccurred(intensity: CGFloat(min(max(intensity, 0.1), 1.0)))
  }

  // MARK: - Helpers

  /// Core Haptics schedules against the engine clock, so a relative delay from
  /// Dart has to be converted to an absolute engine time.
  private func absoluteTime(_ engine: CHHapticEngine, delay: TimeInterval) -> TimeInterval {
    guard delay > 0, delay.isFinite else { return CHHapticTimeImmediate }
    return engine.currentTime + delay
  }

  private func resolveAhapURL(_ path: String) -> URL? {
    let fileManager = FileManager.default
    if path.hasPrefix("/") && fileManager.fileExists(atPath: path) {
      return URL(fileURLWithPath: path)
    }
    let key = FlutterDartProject.lookupKey(forAsset: path)
    if let url = Bundle.main.url(forResource: key, withExtension: nil) {
      return url
    }
    if let resourcePath = Bundle.main.resourcePath {
      let candidate = (resourcePath as NSString).appendingPathComponent(key)
      if fileManager.fileExists(atPath: candidate) {
        return URL(fileURLWithPath: candidate)
      }
    }
    return nil
  }

  private func loadPattern(from url: URL) throws -> CHHapticPattern {
    if #available(iOS 16.0, *) {
      return try CHHapticPattern(contentsOf: url)
    }
    // iOS 13-15: decode the AHAP JSON by hand.
    let data = try Data(contentsOf: url)
    let json = try JSONSerialization.jsonObject(with: data)
    guard let raw = json as? [String: Any] else {
      throw NSError(domain: "AdvancedHaptics", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The AHAP file is not a JSON object."])
    }
    var typed: [CHHapticPattern.Key: Any] = [:]
    for (key, value) in raw {
      typed[CHHapticPattern.Key(rawValue: key)] = value
    }
    return try CHHapticPattern(dictionary: typed)
  }

  private func flutterError(for error: Error) -> FlutterError {
    if let engineError = error as? EngineStateError {
      switch engineError {
      case .unavailable:
        return FlutterError(code: "ENGINE_NIL", message: "Haptic engine is not available.", details: nil)
      case .restartFailed(let underlying):
        return FlutterError(code: "ENGINE_START_FAILED",
                            message: "Failed to restart the haptic engine.",
                            details: underlying.localizedDescription)
      }
    }
    return FlutterError(code: "PLAYBACK_ERROR",
                        message: "Failed to play haptic pattern.",
                        details: error.localizedDescription)
  }

  private func numberArray(_ value: Any?) -> [Double]? {
    guard let list = value as? [Any] else { return nil }
    var numbers: [Double] = []
    numbers.reserveCapacity(list.count)
    for item in list {
      guard let number = item as? NSNumber else { return nil }
      numbers.append(number.doubleValue)
    }
    return numbers
  }

  /// Reads a non-negative, finite double; anything else counts as 0.
  private func doubleArg(_ args: [String: Any], _ key: String) -> Double {
    guard let number = args[key] as? NSNumber else { return 0 }
    let value = number.doubleValue
    return value.isFinite && value > 0 ? value : 0
  }

  private func intArg(_ args: [String: Any], _ key: String, default defaultValue: Int) -> Int {
    (args[key] as? NSNumber)?.intValue ?? defaultValue
  }

  private func log(_ message: String) {
    NSLog("[advanced_haptics] %@", message)
  }
}
