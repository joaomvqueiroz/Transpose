import Flutter
import UIKit

/// Selectors implemented by `TransponoGeckoBridge` (apps/mobile/ios/gecko),
/// which lives in TransponoGecko.framework. The ObjC names are pinned on both
/// sides so this plugin can call it without linking Gecko.
@objc(TransponoGeckoHost)
protocol TransponoGeckoHost: NSObjectProtocol {
  @objc(view) var view: UIView { get }
  @objc(currentUrl) var currentUrl: String? { get }
  @objc(canGoBack) var canGoBack: Bool { get }
  @objc(load:) func load(_ url: String)
  @objc(reload) func reload()
  @objc(goBack) func goBack()
  @objc(evaluate:completion:) func evaluate(
    _ code: String, completion: @escaping (Any?, String?) -> Void)
  @objc(setActive:) func setActive(_ active: Bool)
  @objc(setBackground:) func setBackground(_ color: UIColor)
  @objc(setDecisionHandler:) func setDecisionHandler(
    _ handler: ((String, Bool, @escaping (Bool) -> Void) -> Void)?)
  @objc(close) func close()
}

private enum GeckoBridge {
  typealias EventSink = @convention(block) (NSString, NSDictionary) -> Void
  typealias Factory = @convention(c) (AnyObject, Selector, EventSink) -> AnyObject?
  typealias Flag = @convention(c) (AnyObject, Selector) -> Bool

  static var bridgeClass: AnyClass? { NSClassFromString("TransponoGeckoBridge") }

  static var isRunning: Bool {
    guard let cls = bridgeClass as AnyObject? else { return false }
    let selector = NSSelectorFromString("isRunning")
    guard cls.responds(to: selector), let imp = cls.method(for: selector) else { return false }
    return unsafeBitCast(imp, to: Flag.self)(cls, selector)
  }

  static func make(_ sink: @escaping EventSink) -> TransponoGeckoHost? {
    guard isRunning, let cls = bridgeClass as AnyObject? else { return nil }
    let selector = NSSelectorFromString("makeHostWithEventSink:")
    guard cls.responds(to: selector), let imp = cls.method(for: selector) else { return nil }
    guard let host = unsafeBitCast(imp, to: Factory.self)(cls, selector, sink) else { return nil }
    return unsafeBitCast(host, to: TransponoGeckoHost.self)
  }
}

public class GeckoViewPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "transpono/gecko_view", binaryMessenger: registrar.messenger())
    let plugin = GeckoViewPlugin(messenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.register(
      GeckoPlatformViewFactory(plugin: plugin), withId: "transpono/gecko_view")
  }

  private let messenger: FlutterBinaryMessenger
  private var hosts: [Int: TransponoGeckoHost] = [:]
  private var channels: [Int: FlutterMethodChannel] = [:]
  private var nextId = 1

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func host(_ id: Int) -> TransponoGeckoHost? { hosts[id] }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "isAvailable" {
      result(GeckoBridge.isRunning)
      return
    }
    if call.method == "create" {
      create(result)
      return
    }
    guard let id = (args["id"] as? NSNumber)?.intValue, let host = hosts[id] else {
      result(FlutterError(code: "NO_SESSION", message: "Sessão Gecko inexistente.", details: nil))
      return
    }
    switch call.method {
    case "load":
      guard let url = args["url"] as? String else {
        result(FlutterError(code: "BAD_URL", message: nil, details: nil))
        return
      }
      host.load(url)
      result(nil)
    case "reload":
      host.reload()
      result(nil)
    case "goBack":
      host.goBack()
      result(nil)
    case "canGoBack":
      result(host.canGoBack)
    case "currentUrl":
      result(host.currentUrl)
    case "evaluate":
      let code = args["code"] as? String ?? ""
      host.evaluate(code) { value, error in
        DispatchQueue.main.async {
          if let error {
            let noContext = error.hasPrefix("NO_CONTEXT")
            result(FlutterError(
              code: noContext ? "NO_CONTEXT" : "JS_ERROR", message: error, details: nil))
          } else {
            result(value is NSNull ? nil : value)
          }
        }
      }
    case "setActive":
      host.setActive((args["active"] as? Bool) ?? true)
      result(nil)
    case "setBackgroundColor":
      let argb = (args["color"] as? NSNumber)?.uint32Value ?? 0xFF000000
      host.setBackground(UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255))
      result(nil)
    case "setDecisions":
      let enabled = (args["enabled"] as? Bool) ?? false
      if enabled, let channel = channels[id] {
        host.setDecisionHandler { url, isMainFrame, decide in
          DispatchQueue.main.async {
            channel.invokeMethod("loadRequest", arguments: ["url": url, "isMainFrame": isMainFrame]) {
              response in
              decide((response as? Bool) ?? true)
            }
          }
        }
      } else {
        host.setDecisionHandler(nil)
      }
      result(nil)
    case "dispose":
      host.close()
      hosts.removeValue(forKey: id)
      channels.removeValue(forKey: id)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func create(_ result: @escaping FlutterResult) {
    let id = nextId
    nextId += 1
    let channel = FlutterMethodChannel(
      name: "transpono/gecko_view/\(id)", binaryMessenger: messenger)
    let sink: GeckoBridge.EventSink = { name, payload in
      DispatchQueue.main.async {
        channel.invokeMethod(name as String, arguments: payload)
      }
    }
    guard let host = GeckoBridge.make(sink) else {
      result(FlutterError(
        code: "UNAVAILABLE", message: "O motor Gecko não está nesta versão da app.", details: nil))
      return
    }
    hosts[id] = host
    channels[id] = channel
    result(id)
  }
}

final class GeckoPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: GeckoViewPlugin?

  init(plugin: GeckoViewPlugin) {
    self.plugin = plugin
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let id = ((args as? [String: Any])?["id"] as? NSNumber)?.intValue ?? -1
    return GeckoPlatformView(host: plugin?.host(id))
  }
}

final class GeckoPlatformView: NSObject, FlutterPlatformView {
  private let container = UIView()
  private let host: TransponoGeckoHost?

  init(host: TransponoGeckoHost?) {
    self.host = host
    super.init()
    container.backgroundColor = .black
    guard let host else { return }
    let engineView = host.view
    engineView.removeFromSuperview()
    engineView.frame = container.bounds
    engineView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(engineView)
    host.setActive(true)
  }

  func view() -> UIView { container }
}
