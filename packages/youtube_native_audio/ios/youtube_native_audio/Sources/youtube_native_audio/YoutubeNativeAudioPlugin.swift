import AVFoundation
import Flutter
import UIKit
import YouTubeKit

/// Plays a YouTube video's audio-only track natively so pitch, speed and
/// effects work on iPhone, where WebKit cannot route HLS audio to Web Audio.
/// Dart owns synchronisation: the web player stays the clock and this engine
/// follows it (play/pause/seek), while the web player itself is muted.
public class YoutubeNativeAudioPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "transpose/youtube_native_audio",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(YoutubeNativeAudioPlugin(), channel: channel)
  }

  private let player = NativeTrackPlayer()
  private var loadTask: Task<Void, Never>?
  private var loadToken = 0

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    func number(_ key: String, _ fallback: Double = 0) -> Double {
      guard let value = (args[key] as? NSNumber)?.doubleValue, value.isFinite else { return fallback }
      return value
    }
    switch call.method {
    case "load":
      guard let id = args["videoId"] as? String,
        id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
      else {
        result(FlutterError(code: "INVALID_ID", message: "Vídeo inválido.", details: nil))
        return
      }
      load(id, result)
    case "play":
      do {
        try player.play(from: number("position"))
        result(player.state())
      } catch {
        result(flutterError(error))
      }
    case "pause":
      player.pause()
      result(player.state())
    case "seek":
      player.seek(to: number("position"))
      result(player.state())
    case "configure":
      player.configure(
        pitch: number("pitch"), rate: number("rate", 1),
        bass: number("bass"), mid: number("mid"), treble: number("treble"),
        gain: number("gain"), reverb: number("reverb"),
        delay: number("delay"), feedback: number("feedback"))
      result(nil)
    case "state":
      result(player.state())
    case "stop":
      loadToken += 1
      loadTask?.cancel()
      loadTask = nil
      player.unload()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func load(_ id: String, _ result: @escaping FlutterResult) {
    loadToken += 1
    let token = loadToken
    loadTask?.cancel()
    player.unload()
    loadTask = Task { [weak self] in
      do {
        let url = try await AudioTrackCache.file(for: id)
        await MainActor.run {
          guard let self, token == self.loadToken else {
            result(FlutterError(code: "CANCELLED", message: "Carregamento substituído.", details: nil))
            return
          }
          do {
            let duration = try self.player.load(url)
            result(["duration": duration])
          } catch {
            result(self.flutterError(error))
          }
        }
      } catch {
        await MainActor.run {
          result(FlutterError(
            code: error is CancellationError ? "CANCELLED" : "LOAD_FAILED",
            message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func flutterError(_ error: Error) -> FlutterError {
    FlutterError(code: "NATIVE_AUDIO", message: error.localizedDescription, details: nil)
  }
}

enum NativeAudioError: LocalizedError {
  case noAudioStream
  case http(Int)
  case notLoaded

  var errorDescription: String? {
    switch self {
    case .noAudioStream: return "Este vídeo não tem uma faixa de áudio m4a disponível."
    case .http(let status): return "O download do áudio falhou (HTTP \(status))."
    case .notLoaded: return "O áudio nativo ainda não está carregado."
    }
  }
}

/// Downloads the audio-only m4a once per video into Caches. Range requests in
/// 1 MiB chunks avoid the throttling YouTube applies to single large requests.
enum AudioTrackCache {
  private static let keep = 12
  private static let chunk: Int64 = 1 << 20

  static func file(for id: String) async throws -> URL {
    let directory = try cacheDirectory()
    let target = directory.appendingPathComponent("\(id).m4a")
    let manager = FileManager.default
    if manager.fileExists(atPath: target.path) {
      try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
      return target
    }
    let streams = try await YouTube(videoID: id, methods: [.local]).streams
    guard let stream = streams.filterAudioOnly()
      .filter({ $0.fileExtension == .m4a })
      .highestAudioBitrateStream()
    else { throw NativeAudioError.noAudioStream }

    let partial = directory.appendingPathComponent("\(id).partial")
    try? manager.removeItem(at: partial)
    manager.createFile(atPath: partial.path, contents: nil)
    let handle = try FileHandle(forWritingTo: partial)
    var closed = false
    defer { if !closed { try? handle.close() } }

    var offset: Int64 = 0
    var total: Int64?
    repeat {
      try Task.checkCancellation()
      var request = URLRequest(url: stream.url)
      request.setValue("bytes=\(offset)-\(offset + chunk - 1)", forHTTPHeaderField: "Range")
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw NativeAudioError.http(-1) }
      guard http.statusCode == 200 || http.statusCode == 206 else {
        throw NativeAudioError.http(http.statusCode)
      }
      if data.isEmpty { break }
      try handle.write(contentsOf: data)
      offset += Int64(data.count)
      if http.statusCode == 200 { break }  // Server ignored Range: whole file.
      if total == nil, let range = http.value(forHTTPHeaderField: "Content-Range"),
        let slash = range.lastIndex(of: "/")
      {
        total = Int64(range[range.index(after: slash)...])
      }
      if total == nil { break }
    } while offset < (total ?? 0)

    try handle.close()
    closed = true
    try? manager.removeItem(at: target)
    try manager.moveItem(at: partial, to: target)
    prune(directory)
    return target
  }

  private static func cacheDirectory() throws -> URL {
    let base = try FileManager.default.url(
      for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let directory = base.appendingPathComponent("youtube_native_audio", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private static func prune(_ directory: URL) {
    let manager = FileManager.default
    guard let files = try? manager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return }
    func date(_ url: URL) -> Date {
      (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
    }
    let tracks = files.filter { $0.pathExtension == "m4a" }.sorted { date($0) > date($1) }
    for old in tracks.dropFirst(keep) { try? manager.removeItem(at: old) }
  }
}

/// player -> timePitch -> EQ -> delay -> reverb -> main mixer.
final class NativeTrackPlayer {
  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private let timePitch = AVAudioUnitTimePitch()
  private let eq = AVAudioUnitEQ(numberOfBands: 3)
  private let delay = AVAudioUnitDelay()
  private let reverb = AVAudioUnitReverb()
  private var file: AVAudioFile?
  private var startPosition: Double = 0
  private var playing = false

  init() {
    [node, timePitch, eq, delay, reverb].forEach { engine.attach($0) }
    let low = eq.bands[0]
    low.filterType = .lowShelf
    low.frequency = 200
    let mid = eq.bands[1]
    mid.filterType = .parametric
    mid.frequency = 1000
    mid.bandwidth = 1
    let high = eq.bands[2]
    high.filterType = .highShelf
    high.frequency = 4000
    for band in eq.bands {
      band.gain = 0
      band.bypass = false
    }
    delay.delayTime = 0.28
    delay.lowPassCutoff = 6000
    delay.feedback = 0
    delay.wetDryMix = 0
    reverb.loadFactoryPreset(.mediumHall)
    reverb.wetDryMix = 0
    NotificationCenter.default.addObserver(
      self, selector: #selector(configurationChanged),
      name: .AVAudioEngineConfigurationChange, object: engine)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  var duration: Double {
    guard let file else { return 0 }
    return Double(file.length) / file.processingFormat.sampleRate
  }

  var position: Double {
    guard file != nil else { return 0 }
    guard let renderTime = node.lastRenderTime,
      let playerTime = node.playerTime(forNodeTime: renderTime),
      playerTime.sampleRate > 0
    else { return startPosition }
    return min(duration, startPosition + Double(playerTime.sampleTime) / playerTime.sampleRate)
  }

  func load(_ url: URL) throws -> Double {
    unload()
    let audio = try AVAudioFile(forReading: url)
    let format = audio.processingFormat
    engine.connect(node, to: timePitch, format: format)
    engine.connect(timePitch, to: eq, format: format)
    engine.connect(eq, to: delay, format: format)
    engine.connect(delay, to: reverb, format: format)
    engine.connect(reverb, to: engine.mainMixerNode, format: format)
    file = audio
    startPosition = 0
    return duration
  }

  func unload() {
    node.stop()
    if engine.isRunning { engine.stop() }
    file = nil
    playing = false
    startPosition = 0
  }

  func play(from position: Double) throws {
    guard let file else { throw NativeAudioError.notLoaded }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try session.setActive(true)
    if !engine.isRunning {
      engine.prepare()
      try engine.start()
    }
    schedule(file, from: position)
    node.play()
    playing = true
  }

  func pause() {
    node.pause()
    playing = false
  }

  func seek(to position: Double) {
    guard let file else { return }
    schedule(file, from: position)
    if playing && engine.isRunning { node.play() }
  }

  func configure(
    pitch: Double, rate: Double, bass: Double, mid: Double, treble: Double,
    gain: Double, reverb reverbAmount: Double, delay delayAmount: Double, feedback: Double
  ) {
    timePitch.pitch = Float(min(12, max(-12, pitch)) * 100)
    timePitch.rate = Float(min(2, max(0.25, rate)))
    eq.bands[0].gain = Float(min(12, max(-12, bass)))
    eq.bands[1].gain = Float(min(12, max(-12, mid)))
    eq.bands[2].gain = Float(min(12, max(-12, treble)))
    eq.globalGain = Float(min(6, max(-12, gain)))
    delay.wetDryMix = Float(min(1, max(0, delayAmount / 0.35)) * 60)
    delay.feedback = Float(min(1, max(0, feedback / 0.55)) * 70)
    reverb.wetDryMix = Float(min(1, max(0, reverbAmount / 0.4)) * 60)
  }

  func state() -> [String: Any] {
    [
      "ready": file != nil,
      "playing": playing && node.isPlaying,
      "position": position,
      "duration": duration,
    ]
  }

  private func schedule(_ file: AVAudioFile, from position: Double) {
    node.stop()
    let sampleRate = file.processingFormat.sampleRate
    let clamped = max(0, min(position, duration))
    let start = AVAudioFramePosition(clamped * sampleRate)
    startPosition = Double(start) / sampleRate
    let remaining = file.length - start
    guard remaining > 0 else { return }
    node.scheduleSegment(
      file, startingFrame: start, frameCount: AVAudioFrameCount(remaining), at: nil)
  }

  /// Route changes (headphones, Bluetooth) stop the engine; resume in place.
  @objc private func configurationChanged(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.playing, self.file != nil else { return }
      let resumeAt = self.position
      try? self.play(from: resumeAt)
    }
  }
}
