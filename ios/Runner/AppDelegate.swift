import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KinoExternalDisplay") {
      ExternalDisplayManager.shared.register(messenger: registrar.messenger())
    }
  }
}

// MARK: - External display (AirPlay screen mirroring to Apple TV, HDMI adapters)
//
// When an external screen connects (Control Center → Screen Mirroring →
// Apple TV, or a wired adapter) iOS creates a separate window scene with the
// external-display role because Info.plist declares one. That scene shows
// ONLY the WebRTC video track — a clean feed — while the phone keeps the full
// interface. Nothing here touches capture, recording or the network stream.
//
// flutter_webrtc's classes are reached through the Objective-C runtime so
// this file does not depend on how the plugin's module is packaged
// (Swift Package Manager or CocoaPods).

final class ExternalDisplayManager: NSObject, FlutterStreamHandler {
  static let shared = ExternalDisplayManager()

  private var sink: FlutterEventSink?
  private(set) var window: UIWindow?
  private weak var scene: UIWindowScene?
  private var videoView: UIView?
  private var track: NSObject?
  private var mirror = false
  private var rotation: CGFloat = 0

  func register(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "kinoplayback/external_display", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "status":
        result(self.status())
      case "attach":
        let ok = self.attach(
          trackId: args["trackId"] as? String,
          peerConnectionId: args["peerConnectionId"] as? String,
          mirror: args["mirror"] as? Bool ?? false,
          rotation: CGFloat((args["rotation"] as? NSNumber)?.doubleValue ?? 0))
        result(ok)
      case "transform":
        self.mirror = args["mirror"] as? Bool ?? false
        self.rotation = CGFloat((args["rotation"] as? NSNumber)?.doubleValue ?? 0)
        self.applyTransform()
        result(true)
      case "detach":
        self.detach()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let ev = FlutterEventChannel(name: "kinoplayback/external_display/events", binaryMessenger: messenger)
    ev.setStreamHandler(self)
  }

  // FlutterStreamHandler
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    events(status())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func notify() {
    let s = status()
    DispatchQueue.main.async { self.sink?(s) }
  }

  func status() -> [String: Any] {
    var out: [String: Any] = [
      "connected": scene != nil,
      "active": scene != nil && track != nil,
      "kind": "external",
    ]
    if let screen = scene?.screen {
      out["width"] = Int(screen.nativeBounds.width)
      out["height"] = Int(screen.nativeBounds.height)
      out["name"] = "Внешний экран"
    }
    return out
  }

  // MARK: scene lifecycle

  func sceneConnected(_ ws: UIWindowScene) {
    scene = ws
    let w = UIWindow(windowScene: ws)
    let vc = UIViewController()
    vc.view.backgroundColor = .black
    w.rootViewController = vc
    w.isHidden = false
    window = w
    notify()
  }

  func sceneDisconnected() {
    detach()
    window?.isHidden = true
    window = nil
    scene = nil
    notify()
  }

  // MARK: video

  private func findTrack(_ id: String, _ pcId: String?) -> NSObject? {
    guard let pluginClass = NSClassFromString("FlutterWebRTCPlugin") as? NSObject.Type else { return nil }
    let singletonSel = NSSelectorFromString("sharedSingleton")
    guard pluginClass.responds(to: singletonSel),
          let plugin = pluginClass.perform(singletonSel)?.takeUnretainedValue() as? NSObject else { return nil }
    let byIdSel = NSSelectorFromString("trackForId:peerConnectionId:")
    if plugin.responds(to: byIdSel),
       let t = plugin.perform(byIdSel, with: id, with: pcId)?.takeUnretainedValue() as? NSObject {
      return t
    }
    let remoteSel = NSSelectorFromString("remoteTrackForId:")
    if plugin.responds(to: remoteSel),
       let t = plugin.perform(remoteSel, with: id)?.takeUnretainedValue() as? NSObject {
      return t
    }
    return nil
  }

  private func makeVideoView(frame: CGRect) -> UIView? {
    for name in ["RTCMTLVideoView", "RTCEAGLVideoView"] {
      if let cls = NSClassFromString(name) as? UIView.Type {
        let v = cls.init(frame: frame)
        if v.responds(to: NSSelectorFromString("setVideoContentMode:")) {
          v.setValue(UIView.ContentMode.scaleAspectFit.rawValue, forKey: "videoContentMode")
        }
        return v
      }
    }
    return nil
  }

  func attach(trackId: String?, peerConnectionId: String?, mirror: Bool, rotation: CGFloat) -> Bool {
    guard let id = trackId, let root = window?.rootViewController?.view else { return false }
    guard let t = findTrack(id, peerConnectionId) else { return false }
    let addSel = NSSelectorFromString("addRenderer:")
    guard t.responds(to: addSel) else { return false } // not a video track
    detach()
    guard let v = makeVideoView(frame: root.bounds) else { return false }
    v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    v.backgroundColor = .black
    root.addSubview(v)
    t.perform(addSel, with: v)
    track = t
    videoView = v
    self.mirror = mirror
    self.rotation = rotation
    applyTransform()
    notify()
    return true
  }

  private func applyTransform() {
    guard let v = videoView else { return }
    var tr = CGAffineTransform(rotationAngle: rotation * .pi / 180)
    if mirror { tr = tr.scaledBy(x: -1, y: 1) }
    v.transform = tr
  }

  func detach() {
    if let t = track, let v = videoView {
      let rmSel = NSSelectorFromString("removeRenderer:")
      if t.responds(to: rmSel) { t.perform(rmSel, with: v) }
    }
    videoView?.removeFromSuperview()
    videoView = nil
    track = nil
    notify()
  }
}

/// Scene delegate for the external-display role (see Info.plist).
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options connectionOptions: UIScene.ConnectionOptions) {
    guard let ws = scene as? UIWindowScene else { return }
    ExternalDisplayManager.shared.sceneConnected(ws)
    window = ExternalDisplayManager.shared.window
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    ExternalDisplayManager.shared.sceneDisconnected()
    window = nil
  }
}
