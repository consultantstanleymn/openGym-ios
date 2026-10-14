import SwiftUI
import UIKit
import WebKit

// The shell: one full-screen WKWebView pointed at app://openGym.local/index.html, plus the two
// script handlers the bundle needs.
//
// The structure follows Examples/DemoSimple from the xtool repository: a @main App with a
// UIApplicationDelegateAdaptor, in a SwiftPM library product that xtool turns into an .app. There
// is no storyboard and no Main.storyboard — the view tree is built here in code, which is the
// only way it can be, given xtool has no Interface Builder.

// MARK: - entry point

@main
struct openGymApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            WebRootView()
                // The bundle already accounts for the safe area in CSS (env(safe-area-inset-*)),
                // and openGym draws its own header and bottom tab bar. Letting SwiftUI inset
                // the web view on top of that would double it.
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        }
    }
}

/// The SwiftUI root is only a host. The real view controller is the web view, installed by the
/// app delegate, so that the delegate can own the WKWebView reference the plugins need.
struct WebRootView: View {
    var body: some View {
        Color(red: 0.047, green: 0.055, blue: 0.071)   // #0c0e12, the app background
            .ignoresSafeArea()
            .overlay(alignment: .center) {
                if let webView = AppDelegate.shared?.webView {
                    WebViewContainer(webView: webView)
                        .ignoresSafeArea()
                }
            }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> UIView { webView }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - delegate

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    static private(set) var shared: AppDelegate?

    var window: UIWindow?
    var webView: WKWebView?

    private var bridge: NativeBridge?
    private var schemeHandler: AppSchemeHandler?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppDelegate.shared = self

        let schemeHandler = AppSchemeHandler()
        self.schemeHandler = schemeHandler

        let bridge = NativeBridge()
        self.bridge = bridge
        bridge.connectAppHandler()

        let controller = WKUserContentController()
        // WithReply: iOS 14 and later. The JavaScript side gets a promise, so a Swift throw
        // arrives as a rejection with no id bookkeeping. The two names are the contract with
        // frontend/src/native/bridge.js — ogNative for calls, ogEvents for pushes.
        controller.addScriptMessageHandler(bridge, contentWorld: .page, name: "ogNative")
        controller.add(EventSink(webViewProvider: { [weak self] in self?.webView }),
                     contentWorld: .page, name: "ogEvents")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // A real, stable origin. On file:// the page runs in an opaque origin with no
        // localStorage at all, and openGym keeps its entire state there.
        config.setURLSchemeHandler(schemeHandler, forURLScheme: AppSchemeHandler.scheme)
        // openGym's mobile flavour stores everything locally and talks to no server. Pinning the
        // data store keeps that true even if something else on the device would not.
        config.websiteDataStore = .default()
        // The screen must stay awake during a set: lib/wakelock.js asks for a screen wake lock
        // and the JS feature-detects it, so this only takes effect on iOS 16.4 and later.
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.047, green: 0.055, blue: 0.071, alpha: 1)
        if #available(iOS 17.0, *) {
            webView.isInspectable = true
        }
        self.webView = webView

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = UIColor(red: 0.047, green: 0.055, blue: 0.071, alpha: 1)
        window.rootViewController = UIHostingController(rootView: WebRootView())
        window.makeKeyAndVisible()
        self.window = window

        let start = URL(string: "\(AppSchemeHandler.scheme)://\(AppSchemeHandler.host)/index.html")!
        webView.load(URLRequest(url: start))

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

// MARK: - event sink

/// Pushes an event to the page. Registered as `ogEvents` and called from JavaScript as
/// `window.ogEvents.push(json)`, which the bridge shim's ogNativeDispatch receives.
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

extension NativeBridge {
    /// Gives AppHandler its route back to register and drop listeners, without the bridge
    /// holding a strong reference to a handler that holds a reference to it.
    func connectAppHandler() {
        guard let app = plugins["App"] as? AppHandler else { return }
        app.bridge = self
    }
}