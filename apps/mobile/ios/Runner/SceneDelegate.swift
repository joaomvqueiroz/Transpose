import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// Engine owned by the scene when Gecko, not FlutterAppDelegate, is the
  /// UIApplication delegate (Gecko builds). Plugins register on it here because
  /// FlutterAppDelegate's implicit-engine callback never runs in that mode.
  private var geckoModeEngine: FlutterEngine?
  private var glassBar: TransponoGlassBar?

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
    glassBar = TransponoGlassBar(window: window, messenger: engine.binaryMessenger)
  }
}

/// The bottom bar over the YouTube pages, made of the system's own glass
/// (iOS 26): it bends and blurs what is behind it, edges included, which a
/// page cannot do. Flutter says when it shows, which tab is the current one
/// and the account picture; taps go back to Flutter (channel
/// `transpono/glass_bar`).
final class TransponoGlassBar: NSObject {
  private static let names = ["home", "shorts", "adjust", "you"]

  private let channel: FlutterMethodChannel
  private weak var window: UIWindow?
  private var bar: UIView?
  private var buttons: [String: UIButton] = [:]
  private var shorts: [String: UIImage] = [:]
  private var avatar: UIImage?
  private var avatarURL = ""
  private var selected = ""
  private var shown = false

  init(window: UIWindow, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "transpono/glass_bar", binaryMessenger: messenger)
    self.window = window
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "available":
        if #available(iOS 26.0, *) { result(true) } else { result(false) }
      case "icons":
        self?.setIcons(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "update":
        self?.update(call.arguments as? [String: Any] ?? [:])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setIcons(_ icons: [String: Any]) {
    for (name, value) in icons {
      guard let data = (value as? FlutterStandardTypedData)?.data,
        let image = UIImage(data: data, scale: 3)
      else { continue }
      shorts[name] = image.withRenderingMode(.alwaysTemplate)
    }
    refreshIcons()
  }

  private func update(_ state: [String: Any]) {
    guard #available(iOS 26.0, *), let window = window else { return }
    let visible = state["visible"] as? Bool ?? false
    if bar == nil {
      if !visible { return }
      build(in: window)
    }
    guard let bar = bar else { return }
    window.bringSubviewToFront(bar)
    bar.overrideUserInterfaceStyle = (state["dark"] as? Bool ?? true) ? .dark : .light
    selected = state["selected"] as? String ?? ""
    let url = state["avatar"] as? String ?? ""
    if url != avatarURL {
      avatarURL = url
      avatar = nil
      loadAvatar(url)
    }
    refreshIcons()
    if visible != shown {
      shown = visible
      bar.isUserInteractionEnabled = visible
      UIView.animate(withDuration: 0.22) {
        bar.alpha = visible ? 1 : 0
        bar.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 90)
      }
    }
  }

  @available(iOS 26.0, *)
  private func build(in window: UIWindow) {
    let effect = UIGlassEffect(style: .regular)
    effect.isInteractive = true
    let glass = UIVisualEffectView(effect: effect)
    glass.translatesAutoresizingMaskIntoConstraints = false
    glass.cornerConfiguration = .capsule()
    glass.alpha = 0
    glass.transform = CGAffineTransform(translationX: 0, y: 90)
    window.addSubview(glass)
    let safe = window.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      glass.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
      glass.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
      glass.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -10),
      glass.heightAnchor.constraint(equalToConstant: 52),
    ])
    let row = UIStackView()
    row.axis = .horizontal
    row.distribution = .fillEqually
    row.spacing = 4
    row.translatesAutoresizingMaskIntoConstraints = false
    glass.contentView.addSubview(row)
    glass.contentView.isUserInteractionEnabled = true
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 5),
      row.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -5),
      row.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: 5),
      row.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -5),
    ])
    for name in TransponoGlassBar.names {
      let button = UIButton(type: .system)
      button.tintColor = .label
      button.layer.cornerRadius = 21
      button.layer.cornerCurve = .continuous
      button.imageView?.contentMode = .scaleAspectFit
      button.addAction(
        UIAction { [weak self] _ in self?.channel.invokeMethod("tap", arguments: name) },
        for: .touchUpInside)
      row.addArrangedSubview(button)
      buttons[name] = button
    }
    bar = glass
  }

  private func symbol(_ name: String) -> UIImage? {
    UIImage(
      systemName: name,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .medium))
  }

  private func refreshIcons() {
    guard !buttons.isEmpty else { return }
    buttons["home"]?.setImage(symbol(selected == "home" ? "house.fill" : "house"), for: .normal)
    let reel = shorts[selected == "shorts" ? "shortsFilled" : "shortsOutline"]
    buttons["shorts"]?.setImage(reel ?? symbol("play.square.stack"), for: .normal)
    buttons["adjust"]?.setImage(symbol("slider.horizontal.3"), for: .normal)
    buttons["you"]?.setImage(avatar ?? symbol("person.crop.circle"), for: .normal)
    for (name, button) in buttons {
      button.backgroundColor =
        name == selected ? UIColor.label.withAlphaComponent(0.16) : .clear
    }
  }

  private func loadAvatar(_ text: String) {
    guard let url = URL(string: text), url.scheme == "https" else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data = data, let image = UIImage(data: data) else { return }
      let side: CGFloat = 28
      let round = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
        let box = CGRect(x: 0, y: 0, width: side, height: side)
        UIBezierPath(ovalIn: box).addClip()
        image.draw(in: box)
      }.withRenderingMode(.alwaysOriginal)
      DispatchQueue.main.async {
        guard let self = self, self.avatarURL == text else { return }
        self.avatar = round
        self.refreshIcons()
      }
    }.resume()
  }
}
