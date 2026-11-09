import AVFoundation
import Flutter
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
  }
}
