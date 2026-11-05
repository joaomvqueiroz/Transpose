import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// Engine owned by the scene when Gecko, not FlutterAppDelegate, is the
  /// UIApplication delegate (Gecko builds). Plugins register on it here because
  /// FlutterAppDelegate's implicit-engine callback never runs in that mode.
  private var geckoModeEngine: FlutterEngine?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard !(UIApplication.shared.delegate is FlutterAppDelegate),
      let windowScene = scene as? UIWindowScene
    else {
      super.scene(scene, willConnectTo: session, options: connectionOptions)
      return
    }
    let engine = FlutterEngine(name: "transpono")
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    geckoModeEngine = engine
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    let window = self.window ?? UIWindow(windowScene: windowScene)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    self.window = window
  }
}
