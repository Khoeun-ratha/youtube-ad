import AVFoundation
import AuthenticationServices
import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var native: AdFreeNative?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AdFreeNative.configureAudioSession()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AdFreeNative") {
      native = AdFreeNative(messenger: registrar.messenger())
    }
  }
}

/// iOS side of the platform channels used from Dart. Mirrors MainActivity.kt:
///  - com.adfree.youtube/wakelock: keep playing in the background / screen locked
///  - com.adfree.youtube/cookies:  read / clear youtube.com WebView cookies
///  - com.adfree.youtube/oauth:    Google sign-in through ASWebAuthenticationSession
final class AdFreeNative: NSObject, ASWebAuthenticationPresentationContextProviding {
  private let oauthChannel: FlutterMethodChannel
  private var authSession: ASWebAuthenticationSession?
  private static let defaultOAuthScheme = "com.adfree.youtube.mobileApp"

  init(messenger: FlutterBinaryMessenger) {
    oauthChannel = FlutterMethodChannel(name: "com.adfree.youtube/oauth", binaryMessenger: messenger)
    super.init()

    FlutterMethodChannel(name: "com.adfree.youtube/wakelock", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "acquire":
          AdFreeNative.setAudioSessionActive(true)
          result(true)
        case "release":
          // Keep the session active: deactivating it while the WebView still
          // owns audio would interrupt it. iOS suspends the app by itself once
          // nothing is playing.
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterMethodChannel(name: "com.adfree.youtube/cookies", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        let store = WKWebsiteDataStore.default().httpCookieStore
        switch call.method {
        case "get":
          let args = call.arguments as? [String: Any]
          let host = URL(string: args?["url"] as? String ?? "https://www.youtube.com")?.host ?? "www.youtube.com"
          store.getAllCookies { cookies in
            let header = cookies
              .filter { AdFreeNative.cookie($0, matches: host) }
              .map { "\($0.name)=\($0.value)" }
              .joined(separator: "; ")
            result(header.isEmpty ? nil : header)
          }
        case "clearYouTube":
          // Only youtube.com; accounts.google.com keeps its remembered accounts.
          store.getAllCookies { cookies in
            let targets = cookies.filter { AdFreeNative.isYouTube($0.domain) }
            AdFreeNative.delete(targets, from: store) { result(true) }
          }
        case "clear":
          store.getAllCookies { cookies in
            AdFreeNative.delete(cookies, from: store) { result(true) }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    oauthChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "open":
        let args = call.arguments as? [String: Any]
        guard let raw = args?["url"] as? String, let url = URL(string: raw) else {
          result(FlutterError(code: "bad_args", message: "url missing", details: nil))
          return
        }
        let scheme = (args?["scheme"] as? String) ?? AdFreeNative.defaultOAuthScheme
        self.startSignIn(url: url, scheme: scheme)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Audio

  /// `.playback` lets the WebView's video keep its sound with the silent
  /// switch on and keep playing in the background (UIBackgroundModes: audio).
  static func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
    } catch {
      NSLog("AdFree: audio session category failed: \(error)")
    }
  }

  static func setAudioSessionActive(_ active: Bool) {
    do {
      try AVAudioSession.sharedInstance().setActive(active, options: active ? [] : [.notifyOthersOnDeactivation])
    } catch {
      NSLog("AdFree: audio session activation failed: \(error)")
    }
  }

  // MARK: - Cookies

  static func cookie(_ cookie: HTTPCookie, matches host: String) -> Bool {
    let domain = cookie.domain.lowercased()
    let host = host.lowercased()
    if domain.hasPrefix(".") {
      let bare = String(domain.dropFirst())
      return host == bare || host.hasSuffix(domain)
    }
    return host == domain
  }

  static func isYouTube(_ domain: String) -> Bool {
    let d = domain.lowercased()
    return d == "youtube.com" || d.hasSuffix(".youtube.com")
  }

  static func delete(_ cookies: [HTTPCookie], from store: WKHTTPCookieStore, done: @escaping () -> Void) {
    let group = DispatchGroup()
    for c in cookies {
      group.enter()
      store.delete(c) { group.leave() }
    }
    group.notify(queue: .main, execute: done)
  }

  // MARK: - Google sign-in

  /// Opens Google's account chooser in a Safari sheet (shares Safari's signed-in
  /// Google accounts). Reports the redirect URL back to Dart, or
  /// `<scheme>:/oauth2redirect?error=access_denied` when the user cancels.
  private func startSignIn(url: URL, scheme: String) {
    authSession?.cancel()
    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.authSession = nil
        let redirect = callback?.absoluteString
          ?? "\(scheme):/oauth2redirect?error=\(error == nil ? "unknown" : "access_denied")"
        self.oauthChannel.invokeMethod("redirect", arguments: redirect)
      }
    }
    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = false
    authSession = session
    if !session.start() {
      authSession = nil
      oauthChannel.invokeMethod("redirect", arguments: "\(scheme):/oauth2redirect?error=access_denied")
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    return windows.first(where: { $0.isKeyWindow }) ?? windows.first ?? ASPresentationAnchor()
  }
}
