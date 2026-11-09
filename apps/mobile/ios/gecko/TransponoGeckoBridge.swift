// TransponoGecko.framework: the only Transpono code that links GeckoView.
//
// Built in CI (.github/workflows/ios-gecko.yml) against the Gecko engine kit
// (Reynard 0.20.0's GeckoView wrapper, GPL-3.0, over Firefox's Gecko,
// MPL-2.0). Runner's entry point dlopen()s this framework and calls
// `transpono_gecko_main`; the gecko_view Flutter plugin then finds
// `TransponoGeckoBridge` at run time. ObjC selector names are pinned to match
// the plugin's `TransponoGeckoHost` protocol.

import Foundation
import GeckoView
import UIKit

private var geckoRunning = false

/// Starts Gecko as the process owner. Gecko's AppShellDelegate becomes the
/// UIApplication delegate and the scene manifest's SceneDelegate shows Flutter.
/// Never returns.
@_cdecl("transpono_gecko_main")
public func transpono_gecko_main(
  _ argc: Int32,
  _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) {
  geckoRunning = true
  JITLessReporter.start()
  GeckoRuntime.main(argc: argc, argv: argv)
}

/// Gecko content processes wait (up to 5 s each) for the parent to say
/// whether a debugger enabled JIT for them. Transpono never enables JIT
/// (Reynard's pairing flow is not included), so answer "no JIT" at once.
private enum JITLessReporter {
  static var observer: NSObjectProtocol?

  static func start() {
    observer = NotificationCenter.default.addObserver(
      forName: Notification.Name("GeckoRuntime.ChildProcessDidStart"),
      object: nil, queue: nil
    ) { note in
      guard let pid = (note.userInfo?["pid"] as? NSNumber)?.int32Value, pid > 0 else { return }
      let version = ProcessInfo.processInfo.operatingSystemVersion
      ReportJITStatusForChild(
        pid, false,
        JITRuntimeInfo(
          hasTXMSupport: 0,
          deviceOSVersion: DeviceOSVersion(
            majorVersion: Int32(version.majorVersion),
            minorVersion: Int32(version.minorVersion),
            patchVersion: Int32(version.patchVersion))))
    }
  }
}

@objc(TransponoGeckoBridge)
public final class TransponoGeckoBridge: NSObject, NavigationDelegate, ProgressDelegate,
  AddonMessageDelegate, AddonPortDelegate
{
  public typealias EventSink = (String, [String: Any]) -> Void
  public typealias DecisionHandler = (String, Bool, @escaping (Bool) -> Void) -> Void

  static let extensionID = "transpono-gecko@transpono.app"
  // The only resource://app location Reynard's Gecko accepts for a built-in
  // extension (see embed-gecko.sh); our relay is installed there.
  static let extensionLocation = "resource://app/extensions/readerview/"
  static let nativeApp = "transpono"

  @MainActor private static var extensionTask: Task<Void, Never>?
  // Written on the main actor; read from the main thread (method channel).
  private static var extensionReady = false
  private static var extensionError: String?

  @objc(isRunning) public static var isRunning: Bool { geckoRunning }

  // Google cookies copied from Safari's engine (main thread only), waiting
  // for a page whose relay extension can set them; and the open sessions.
  private static var stagedCookies: [[String: Any]] = []
  private static let openHosts = NSHashTable<TransponoGeckoBridge>.weakObjects()

  /// Google refuses to sign in on Gecko without JIT, but signs in in Safari's
  /// engine: the plugin hands over that session's cookies here. They are set
  /// through the relay extension (background `cookies` API) as soon as a page
  /// is connected, then the page reloads signed in.
  @objc(stageCookies:)
  public static func stageCookies(_ cookies: NSArray) -> Int {
    stagedCookies = cookies.compactMap { $0 as? [String: Any] }
    let count = stagedCookies.count
    openHosts.allObjects.forEach { $0.applyStagedCookies() }
    return count
  }

  private func applyStagedCookies() {
    guard !Self.stagedCookies.isEmpty, let port, !closed else { return }
    let cookies = Self.stagedCookies
    Self.stagedCookies = []
    port.postMessage(["type": "setCookies", "cookies": cookies])
  }

  /// Present as Firefox for Android, exactly as Reynard does by default
  /// (UserAgentPolicy.defaultConfiguration, "useAndroidUserAgent" on).
  /// Without it Gecko reports its own iOS identity, which YouTube does not
  /// expect from this engine: playback then stops after about a minute
  /// ("Algo correu mal") and seeking past it fails, while Reynard plays on.
  static var androidMobileMode: WebsiteModeSetting {
    let major =
      GeckoRuntime.version.split(whereSeparator: { !$0.isNumber }).first.map(String.init)
      ?? "159"
    return WebsiteModeSetting(
      userAgentOverride:
        "Mozilla/5.0 (Android 15; Mobile; rv:\(major).0) Gecko/\(major).0 Firefox/\(major).0",
      platformOverride: "Linux armv81",
      appVersionOverride: "5.0 (Android 15)",
      oscpuOverride: "Linux armv81",
      buildIDOverride: nil,
      userAgentMode: 0,
      viewportMode: 0)
  }

  @objc(makeHostWithEventSink:)
  public static func makeHost(eventSink: @escaping EventSink) -> TransponoGeckoBridge? {
    guard geckoRunning else { return nil }
    return TransponoGeckoBridge(eventSink: eventSink)
  }

  private let sink: EventSink
  private let session: GeckoSession
  private let geckoView = GeckoView()
  private var port: AddonPort?
  private var pending: [Int: (Any?, String?) -> Void] = [:]
  private var nextEval = 1
  private var decide: DecisionHandler?
  private var url: String?
  private var back = false
  private var closed = false
  private var rejectedPorts = 0

  private init(eventSink: @escaping EventSink) {
    sink = eventSink
    session = GeckoSession(
      settings: GeckoSessionSettings(
        websiteMode: Self.androidMobileMode,
        pageZoom: .default,
        language: LanguageSetting(codes: ["pt-PT", "pt", "en"])))
    super.init()
    geckoView.backgroundColor = .black
    session.navigationDelegate = self
    session.progressDelegate = self
    session.setAddonMessageDelegate(
      self, extensionID: Self.extensionID, nativeApp: Self.nativeApp)
    session.open()
    Self.openHosts.add(self)
    geckoView.session = session
    session.setActive(true)
    session.setFocused(true)
    Task { @MainActor in await Self.ensureExtension() }
  }

  @MainActor private static func ensureExtension() async {
    if extensionTask == nil {
      extensionTask = Task { @MainActor in
        do {
          _ = try await AddonRuntime.shared.ensureBuiltIn(
            location: extensionLocation, id: extensionID)
        } catch {
          NSLog("Transpono: Gecko bridge extension failed: %@", "\(error)")
          extensionError = String("\(error)".prefix(120))
        }
        extensionReady = true
      }
    }
    await extensionTask?.value
  }

  // MARK: TransponoGeckoHost

  @objc(view) public var view: UIView { geckoView }
  @objc(currentUrl) public var currentUrl: String? { url }
  @objc(canGoBack) public var canGoBack: Bool { back }

  /// Loads at once. The relay extension installs alongside; its install has no
  /// timeout, so waiting for it could leave the page never loading. If it
  /// finishes after the page started, reload once so the relay content script
  /// (document_start) is present for the bridge.
  @objc(load:) public func load(_ target: String) {
    session.load(target)
    Task { @MainActor in
      let alreadyInstalled = Self.extensionReady
      await Self.ensureExtension()
      guard !self.closed, !alreadyInstalled, self.port == nil else { return }
      self.session.reload()
    }
  }

  @objc(reload) public func reload() { session.reload() }
  @objc(goBack) public func goBack() { session.goBack() }
  @objc(setActive:) public func setActive(_ active: Bool) {
    session.setActive(active)
    session.setFocused(active)
  }
  @objc(setBackground:) public func setBackground(_ color: UIColor) {
    geckoView.backgroundColor = color
  }
  @objc(setDecisionHandler:) public func setDecisionHandler(_ handler: DecisionHandler?) {
    decide = handler
  }

  @objc(evaluate:completion:)
  public func evaluate(_ code: String, completion: @escaping (Any?, String?) -> Void) {
    guard let port, !closed else {
      // Say why, so the app can show it: the relay extension's install state
      // and whether its content script ever tried to connect.
      let install: String
      if let failure = Self.extensionError {
        install = "extensão falhou: \(failure)"
      } else {
        install = Self.extensionReady ? "extensão instalada" : "extensão a instalar"
      }
      completion(
        nil,
        "NO_CONTEXT: sem ligação à página (\(install); ligações recusadas: \(rejectedPorts)).")
      return
    }
    let id = nextEval
    nextEval += 1
    pending[id] = completion
    port.postMessage(["type": "eval", "id": id, "code": code])
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      self?.pending.removeValue(forKey: id)?(nil, "JS timeout")
    }
  }

  @objc(close) public func close() {
    guard !closed else { return }
    closed = true
    failPending("NO_CONTEXT: sessão fechada.")
    port?.disconnect()
    port = nil
    session.setAddonMessageDelegate(
      nil, extensionID: Self.extensionID, nativeApp: Self.nativeApp)
    session.navigationDelegate = nil
    session.progressDelegate = nil
    geckoView.session = nil
    session.close()
  }

  private func failPending(_ reason: String) {
    let waiting = pending
    pending.removeAll()
    waiting.values.forEach { $0(nil, reason) }
  }

  private func emit(_ name: String, _ payload: [String: Any] = [:]) {
    guard !closed else { return }
    sink(name, payload)
  }

  // MARK: Extension port (relay.js content script ↔ app)

  public func addonPortDidConnect(_ port: AddonPort) {
    guard port.sender.extensionID == Self.extensionID, port.sender.isTopLevel,
      port.sender.session === session
    else {
      rejectedPorts += 1
      port.disconnect()
      return
    }
    if let old = self.port, old !== port {
      old.disconnect()
      failPending("NO_CONTEXT: a página mudou.")
    }
    port.delegate = self
    self.port = port
    applyStagedCookies()
  }

  public func addonPort(_ port: AddonPort, didReceive message: Any) {
    guard port === self.port, let payload = message as? [String: Any?] else { return }
    func field(_ key: String) -> Any? { payload[key] ?? nil }
    switch field("type") as? String {
    case "result":
      let rawId = field("id")
      guard let id = (rawId as? NSNumber)?.intValue ?? (rawId as? Int),
        let done = pending.removeValue(forKey: id)
      else { return }
      if (field("ok") as? Bool) == true || (field("ok") as? NSNumber)?.boolValue == true {
        done(field("value") ?? NSNull(), nil)
      } else {
        done(nil, (field("error") as? String) ?? "Erro de JavaScript.")
      }
    case "cookiesSet":
      // The session is now in Gecko's cookie store: reload to use it.
      emit("cookiesImported", [
        "ok": (field("ok") as? NSNumber)?.intValue ?? 0,
        "failed": (field("failed") as? NSNumber)?.intValue ?? 0,
      ])
      session.reload()
    case "channel":
      emit("channel", [
        "name": (field("name") as? String) ?? "",
        "message": (field("message") as? String) ?? "",
      ])
    default:
      break
    }
  }

  public func addonPortDidDisconnect(_ port: AddonPort) {
    guard port === self.port else { return }
    self.port = nil
    failPending("NO_CONTEXT: a página mudou.")
  }

  // MARK: Navigation

  public func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {
    self.url = url
    emit("location", ["url": url ?? ""])
  }

  public func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
    back = canGoBack
    emit("canGoBack", ["value": canGoBack])
  }

  public func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
    let allowed: Bool
    if let decide {
      allowed = await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
          decide(request.uri, true) { continuation.resume(returning: $0) }
        }
      }
    } else {
      allowed = true
    }
    guard allowed else { return .deny }
    // There is only one page in Transpono: links and sign-in steps that ask
    // for a new window or tab open here instead of going nowhere.
    if request.target != .current {
      let target = request.uri
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.closed else { return }
        self.session.load(target)
      }
      return .deny
    }
    return .allow
  }

  public func onLoadError(session: GeckoSession, error: WebRequestError) -> String? {
    emit("loadError", ["description": "\(error)", "url": url ?? ""])
    return nil
  }

  // MARK: Progress

  public func onPageStart(session: GeckoSession, url: String) {
    self.url = url
    emit("pageStart", ["url": url])
  }

  public func onPageStop(session: GeckoSession, success: Bool) {
    emit("pageStop", ["success": success])
  }

  public func onProgressChange(session: GeckoSession, progress: Int) {
    emit("progress", ["value": progress])
  }
}
