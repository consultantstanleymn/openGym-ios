import UIKit
import WebKit

// The shell: one full-screen WKWebView pointed at app://openGym.local/index.html, plus the script
// handlers the bundle needs.
//
// Plain UIKit, with @main on the AppDelegate. The earlier version used the SwiftUI pattern from
// xtool's Examples/DemoSimple — a Scene whose body read AppDelegate.shared?.webView — and it
// rendered a blank screen. SwiftUI evaluates a scene's body once; that read happened before the
// delegate had built anything, and nothing invalidated the view afterwards, so the app sat on
// Color.appBackground forever. Owning the window here means there is no ordering to get right:
// didFinishLaunching builds the web view and installs it as the root, and that is the whole story.
//
// There is still no storyboard and no Main.storyboard — xtool has no Interface Builder.

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private(set) var webView: WKWebView?

    private var bridge: NativeBridge?
    private var schemeHandler: AppSchemeHandler?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppDelegate.current = self
        NSLog("og: didFinishLaunching")

        let schemeHandler = AppSchemeHandler()
        self.schemeHandler = schemeHandler

        let bridge = NativeBridge()
        self.bridge = bridge
        bridge.connectAppHandler()

        let controller = WKUserContentController()
        // ogNative is a WithReply handler, so JavaScript gets a promise and a Swift throw becomes
        // a rejection. ogEvents is a plain handler the shell pushes to. ogConsole forwards the
        // page's own warnings and errors. The three names are the contract with
        // frontend/src/native/bridge.js.
        controller.addScriptMessageHandler(bridge, contentWorld: .page, name: "ogNative")
        controller.add(EventSink(webViewProvider: { [weak self] in self?.webView }),
                       contentWorld: .page, name: "ogEvents")
        controller.add(ConsoleSink.shared, contentWorld: .page, name: "ogConsole")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // A real, stable origin. On file:// the page runs in an opaque origin with no
        // localStorage at all, and openGym keeps its entire state there.
        config.setURLSchemeHandler(schemeHandler, forURLScheme: AppSchemeHandler.scheme)
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .appBackground
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if #available(iOS 17.0, *) {
            // Lets Safari's Web Inspector attach over USB when a Developer Disk Image is mounted.
            // Harmless without one, and the only way to debug the page on device when it is not.
            webView.isInspectable = true
        }
        self.webView = webView
        NSLog("og: webView built")

        // ScreenshotWindow, not UIWindow: the shake has to be caught above the WKWebView, which
        // consumes motion events long before they reach a view controller. See Screenshot.swift.
        let window = ScreenshotWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = .appBackground
        // The web view is the root view controller's view, not a child: it has to own the safe
        // area and the scroll insets the page negotiates itself.
        window.rootViewController = UIViewController()
        window.rootViewController?.view = webView
        window.snapshotTarget = webView
        window.makeKeyAndVisible()
        self.window = window
        bridge.installSnapshot(on: window)
        NSLog("og: window shown")

        if let url = URL(string: "\(AppSchemeHandler.scheme)://\(AppSchemeHandler.host)/index.html") {
            NSLog("og: loading \(url.absoluteString)")
            webView.load(URLRequest(url: url))
        } else {
            NSLog("og: FAILED to build start URL")
        }

        return true
    }

    // MARK: - lifecycle

    // The reminder window is rebuilt whenever the app comes forward, and the account state is
    // pulled again (lib/mobile.js onAppActive). Both hang off this one event.
    func applicationWillEnterForeground(_ application: UIApplication) {
        bridge?.emit("appStateChange", ["isActive": true])
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        bridge?.emit("appStateChange", ["isActive": false])
    }
}

extension UIColor {
    /// #0c0e12 — the app background, and the colour the web bundle draws behind itself.
    static let appBackground = UIColor(red: 0.047, green: 0.055, blue: 0.071, alpha: 1)
}

// MARK: - reaching the window from a plugin

// The plugins present the share sheet and the print sheet, and AppHandler pushes events into the
// web view, so they need a route back to the live UI without the delegate holding them strongly.

extension AppDelegate {
    static private(set) var current: AppDelegate?

    /// The view controller to present from. Going through the topmost presented controller
    /// matters: Settings-style sheets are presented modally over the web view, and presenting on
    /// the root while one is already up fails.
    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = current?.window
            ?? scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
            ?? scenes.flatMap { $0.windows }.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - navigation logging

// WKNavigationDelegate, so a load that fails says why instead of leaving a blank screen.
extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NSLog("og: nav didStart")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        NSLog("og: nav didCommit")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("og: nav didFinish")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("og: nav FAILED \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        NSLog("og: nav FAILED-PROVISIONAL \(error.localizedDescription)")
    }
}

// MARK: - event sink

/// Pushes an event to the page. Registered as `ogEvents` and called from JavaScript, which
/// forwards it to window.ogNativeDispatch in bridge.js.
private final class EventSink: NSObject, WKScriptMessageHandler {
    private let webViewProvider: () -> WKWebView?

    init(webViewProvider: @escaping () -> WKWebView?) {
        self.webViewProvider = webViewProvider
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let json = message.body as? String else { return }
        webViewProvider()?.evaluateJavaScript("window.ogNativeDispatch(\(json))")
    }
}

/// Forwards the page's console into the device log, so a JavaScript exception during boot is
/// visible instead of leaving a blank screen with no clue.
final class ConsoleSink: NSObject, WKScriptMessageHandler {
    static let shared = ConsoleSink()

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        let level = body["level"] as? String ?? "log"
        let text = body["text"] as? String ?? ""
        if level == "error" || level == "warn" { NSLog("og: page \(level): \(text)") }
    }
}

extension NativeBridge {
    /// Gives AppHandler its route back to register and drop listeners, without the bridge
    /// holding a strong reference to a handler that holds a reference to it.
    func connectAppHandler() {
        guard let app = plugins["App"] as? AppHandler else { return }
        app.bridge = self
    }
}