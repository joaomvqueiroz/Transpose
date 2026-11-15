import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// Process entry point.
///
/// Builds that embed TransponoGecko.framework (CI workflow ios-gecko) start
/// Gecko first: it must own process start-up, and its AppShellDelegate then
/// becomes the UIApplication delegate. The scene manifest's SceneDelegate
/// shows Flutter in both modes. Without the framework, start as a normal
/// Flutter app.
@main
enum TransponoMain {
  typealias GeckoMain = @convention(c) (
    Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
  ) -> Void

  static func main() {
    // The video's sound keeps playing with the app in the background
    // (Info.plist UIBackgroundModes: audio). Category only: the session
    // becomes active when something plays, so opening the app does not
    // stop another app's music.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    if let frameworks = Bundle.main.privateFrameworksPath,
      let handle = dlopen(
        frameworks + "/TransponoGecko.framework/TransponoGecko", RTLD_NOW | RTLD_GLOBAL),
      let symbol = dlsym(handle, "transpono_gecko_main")
    {
      unsafeBitCast(symbol, to: GeckoMain.self)(CommandLine.argc, CommandLine.unsafeArgv)
      return
    }
    _ = UIApplicationMain(
      CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
  }
}

@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    TransponoNative.register(with: engineBridge.pluginRegistry)
  }
}

/// The app's own iPhone channels, the same ones MainActivity.kt answers on
/// Android: `transpono/background` (lock screen and Control Center) and
/// `transpono/external` (links that open in Safari or another app).
enum TransponoNative {
  private static var background: TransponoBackground?

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "TransponoNative") else { return }
    let messenger = registrar.messenger()
    background = TransponoBackground(messenger: messenger)
    let external = FlutterMethodChannel(name: "transpono/external", binaryMessenger: messenger)
    external.setMethodCallHandler { call, result in
      guard call.method == "open",
        let text = (call.arguments as? [String: Any])?["url"] as? String,
        let url = URL(string: text)
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      }
    }
  }
}

/// The song in the background on the iPhone: its name, position and
/// play/pause, next and previous on the lock screen, in Control Center and
/// on headphones (the Android notification's counterpart). Taps go back to
/// Flutter as "play", "pause", "next", "previous" or "seek:<ms>".
final class TransponoBackground: NSObject {
  private let channel: FlutterMethodChannel
  private var targets: [(MPRemoteCommand, Any)] = []
  private var playing = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "transpono/background", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "update":
        self.update(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "stop":
        self.stop()
        result(nil)
      case "log":
        // The sound's steps, readable from a computer over USB (the
        // phone's system log); nothing of it is shown in the app.
        NSLog("TransponoSom: %@", call.arguments as? String ?? "")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // Headphones or a Bluetooth speaker went away: pause, as Android does,
    // rather than carry on out loud through the phone's speaker.
    NotificationCenter.default.addObserver(
      self, selector: #selector(routeChanged(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)
  }

  @objc private func routeChanged(_ note: Notification) {
    guard
      let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
    else { return }
    DispatchQueue.main.async { self.send("pause") }
  }

  private func send(_ action: String) {
    channel.invokeMethod("action", arguments: action)
  }

  private func update(_ args: [String: Any]) {
    if targets.isEmpty { addTargets() }
    playing = args["playing"] as? Bool ?? false
    let speed = (args["speed"] as? NSNumber)?.doubleValue ?? 1
    let position = ((args["position"] as? NSNumber)?.doubleValue ?? 0) / 1000
    let duration = ((args["duration"] as? NSNumber)?.doubleValue ?? 0) / 1000
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: args["title"] as? String ?? "",
      MPMediaItemPropertyArtist: args["artist"] as? String ?? "",
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
    ]
    if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func addTargets() {
    let center = MPRemoteCommandCenter.shared()
    // Play and pause are sent as what they mean, never as "toggle": the page
    // may report its own controls too, and a toggle received twice would
    // undo itself.
    func add(_ command: MPRemoteCommand, _ action: @escaping (MPRemoteCommandEvent) -> String?) {
      command.isEnabled = true
      let target = command.addTarget { [weak self] event in
        guard let self = self, let name = action(event) else { return .commandFailed }
        self.send(name)
        return .success
      }
      targets.append((command, target))
    }
    add(center.playCommand) { _ in "play" }
    add(center.pauseCommand) { _ in "pause" }
    add(center.togglePlayPauseCommand) { [weak self] _ in
      (self?.playing ?? false) ? "pause" : "play"
    }
    add(center.nextTrackCommand) { _ in "next" }
    add(center.previousTrackCommand) { _ in "previous" }
    add(center.changePlaybackPositionCommand) { event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return nil }
      return "seek:\(Int(event.positionTime * 1000))"
    }
    center.skipForwardCommand.isEnabled = false
    center.skipBackwardCommand.isEnabled = false
  }

  private func stop() {
    for (command, target) in targets {
      command.removeTarget(target)
      command.isEnabled = false
    }
    targets.removeAll()
    playing = false
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }
}
