import Foundation
import WebKit

// The single message channel between the web bundle and native code.
//
// The bundle reaches this through `window.webkit.messageHandlers.ogNative.postMessage(...)`,
// registered with WKScriptMessageHandlerWithReply, which is iOS 14 and later. That API is a
// promise on the JavaScript side, so a Swift `throw` arrives in JS as a rejection — no id
// bookkeeping, no timeout to leak, and an error that keeps its message.
//
// Every handler is synchronous on the main actor. Nothing here touches the network or sleeps, so
// there is nothing to move off it, and keeping one actor removes a whole class of ordering bug
// between a file write and a notification schedule that the web layer asked for in sequence.

@MainActor
// The ObjC selector is didReceiveScriptMessage:replyHandler:; Swift imports it as `didReceive:`,
// the same name the plain WKScriptMessageHandler uses. The difference is the replyHandler, which
// the header marks WK_SWIFT_UI_ACTOR — so the closure is @MainActor too, and the class matches.
final class NativeBridge: NSObject, WKScriptMessageHandlerWithReply {

    /// Handlers, keyed plugin then method: "Filesystem" -> "readFile".
    private var handlers: [String: [String: ([String: Any]) throws -> Any]] = [:]

    /// Plugin instances, so AppHandler can reach the bridge to register and drop listeners
    /// without the bridge holding a strong reference to itself.
    /// Internal, not private: AppDelegate and AppHandler both reach in.
    var plugins: [String: NativePlugin] = [:]

    /// Live addListener callbacks. The web side never hands a function across the boundary; it
    /// registers an id here and native pushes an event name to it (see `emit`).
    private var listeners: [String: (String) -> Void] = [:]   // event -> (id) -> Void

    override init() {
        super.init()
        let app = AppHandler()
        plugins["App"] = app
        register(FilesystemHandler(), as: "Filesystem")
        register(app, as: "App")
        register(NotificationHandler(), as: "LocalNotifications")
        register(ShareHandler(), as: "Share")
        register(SecureStorageHandler(), as: "SecureStorage")
        register(PrintHandler(), as: "Print")
    }

    private func register(_ handler: NativePlugin, as name: String) {
        handlers[name] = handler.methods
        plugins[name] = handler
    }

    // The reply values are restricted by WebKit to NSNumber, NSNull, NSString, NSDate, NSArray
    // and NSDictionary — and containers may only hold those. Everything returned here is a plain
    // dictionary of strings and numbers, which is inside that set. A Swift struct or a URL would
    // be silently dropped rather than throw, so nothing but those types comes back.
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any],
              let plugin = body["plugin"] as? String,
              let method = body["method"] as? String
        else {
            replyHandler(nil, "malformed native call: expected plugin and method")
            return
        }

        let args = body["args"] as? [String: Any] ?? [:]

        guard let table = handlers[plugin] else {
            // Reached by registerPlugin for an Android-only plugin — RestAlert, SystemBars,
            // Install, BackupFolder, HealthConnect. openGym gates all five behind isAndroid() and
            // resolves them to null before calling, so landing here means a caller changed.
            replyHandler(nil, "no native handler for \(plugin).\(method)")
            return
        }
        guard let fn = table[method] else {
            replyHandler(nil, "\(plugin).\(method) is not implemented")
            return
        }

        do {
            replyHandler(try fn(args), nil)
        } catch {
            replyHandler(nil, String(describing: error))
        }
    }

    /// Push an event to whatever addListener registered for it. Called when the app returns to
    /// the foreground, which is the only event openGym subscribes to (appStateChange).
    func emit(_ event: String, _ payload: [String: Any]) {
        guard let fn = listeners[event] else { return }
        let body: [String: Any] = ["event": event, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8)
        else { return }
        fn(json)
    }

    func addListener(_ event: String, _ handler: @escaping (String) -> Void) {
        listeners[event] = handler
    }

    func removeListener(_ event: String) {
        listeners[event] = nil
    }
}

/// A group of methods under one plugin name.
///
/// Main-actor isolated, because every handler it is implemented by touches UIKit, the Keychain or
/// UNUserNotificationCenter. Under Swift 6 a nonisolated protocol with an actor-isolated
/// conformance is a data race, not a warning.
@MainActor
protocol NativePlugin {
    var methods: [String: ([String: Any]) throws -> Any] { get }
}

/// The one error every handler throws, carrying the message the web layer will show.
struct NativeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - argument helpers
//
// The payload arrives as JSON, so a number is NSNumber and a bool is NSNumber too. These keep the
// coercions in one place instead of spreading `as? Int ?? 0` across six files.

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
    func requiredString(_ key: String) throws -> String {
        guard let v = self[key] as? String, !v.isEmpty else {
            throw NativeError("\(key) is required")
        }
        return v
    }
    func int(_ key: String) -> Int? {
        if let n = self[key] as? NSNumber { return n.intValue }
        return nil
    }
    func double(_ key: String) -> Double? {
        if let n = self[key] as? NSNumber { return n.doubleValue }
        return nil
    }
    func bool(_ key: String) -> Bool? {
        if let n = self[key] as? NSNumber { return n.boolValue }
        return nil
    }
    func array(_ key: String) -> [Any] { self[key] as? [Any] ?? [] }
    func dict(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    /// A Date that bridge.js encoded as { "@date": <ms since epoch> }.
    func date(_ key: String) -> Date? {
        guard let wrapped = dict(key)["@date"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: wrapped.doubleValue / 1000.0)
    }
}