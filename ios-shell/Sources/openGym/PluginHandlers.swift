import Foundation
import Security
import UIKit

// App, Share, SecureStorage and Print — the four small handlers.

// MARK: - App

/// openGym subscribes to one event: appStateChange, so it can resync the reminder window and pull
/// account state when the phone comes back to the foreground. No closure crosses the boundary —
/// the web side registers an id and native pushes JSON to it (see NativeBridge.emit).
@MainActor
// A class, not a struct: it holds a weak back-reference to the bridge so addListener
// can register an event. A struct held in a dictionary is a copy, so the assignment
// would be written to a temporary and thrown away.
final class AppHandler: NativePlugin {
    weak var bridge: NativeBridge?

    var methods: [String: ([String: Any]) throws -> Any] {
        ["addListener": addListener,
        "removeListener": removeListener,
        "removeAllListeners": removeAllListeners,
        "exitApp": exitApp,
        "getInfo": getInfo,
        "getLaunchUrl": getLaunchUrl,
        ]
    }

    func addListener(_ args: [String: Any]) throws -> Any {
        let event = try args.requiredString("event")
        let id = UUID().uuidString
        // The callback reaches JavaScript through the ogEvents script handler installed in
        // AppDelegate; see makeEventSink().
        bridge?.addListener(event) { [weak self] json in
            self?.deliver(json)
        }
        return ["id": id]
    }

    func removeListener(_ args: [String: Any]) throws -> Any {
        // Only appStateChange is ever registered, so removing by id means clearing the one slot.
        bridge?.removeListener("appStateChange")
        return [:]
    }

    func removeAllListeners(_ args: [String: Any]) throws -> Any {
        bridge?.removeListener("appStateChange")
        return [:]
    }

    func exitApp(_ args: [String: Any]) throws -> Any {
        DispatchQueue.main.async { exit(0) }
        return [:]
    }

    func getInfo(_ args: [String: Any]) throws -> Any {
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "id": "ch.stanley.opengym",
            "build": info["CFBundleVersion"] as? String ?? "1",
            "version": info["CFBundleShortVersionString"] as? String ?? "1.0.0",
        ]
    }

    func getLaunchUrl(_ args: [String: Any]) throws -> Any {
        // Nothing launches this app from a URL — openGym's mobile flavour has no deep links —
        // so the honest answer is the Capacitor one, an empty href.
        ["href": ""]
    }

    private func deliver(_ json: String) {
        guard let webView = AppDelegate.current?.webView else { return }
        let js = "window.ogNativeDispatch && window.ogNativeDispatch(\(json))"
        webView.evaluateJavaScript(js)
    }
}

// MARK: - Share

/// WKWebView cannot download a blob URL, so a backup export goes out as a file in Caches/ and
/// through the share sheet (Files, AirDrop, mail). See shareExport and shareExportBlob in
/// lib/mobile.js.
@MainActor
struct ShareHandler: NativePlugin {
    var methods: [String: ([String: Any]) throws -> Any] {
    [
        "share": share,
    ]
}

    func share(_ args: [String: Any]) throws -> Any {
        guard let urlString = args.string("url"),
              let url = URL(string: urlString)
        else {
            throw NativeError("share needs a url")
        }
        guard let root = AppDelegate.topViewController() else {
            throw NativeError("no view controller to present from")
        }

        var items: [Any] = [url]
        if let text = args.string("text") { items.insert(text, at: 0) }

        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires an anchor or the sheet raises rather than presenting.
        sheet.popoverPresentationController?.sourceView = root.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
        sheet.popoverPresentationController?.permittedArrowDirections = []

        root.present(sheet, animated: true)
        return ["activityType": NSNull()]
    }
}

// MARK: - SecureStorage

/// The Keychain, for exactly two secrets: the Coach's provider API key and the Cloudflare Access
/// service token. lib/coach-secrets.js is explicit that these must never reach the synced state S,
/// never sit in localStorage, and never appear in an export — which is why they are here rather
/// than in a JSON file the web layer can read.
///
/// Accessibility is afterFirstUnlock, matching the entitlements file: the notification window is
/// written in the foreground and read back by UNUserNotificationCenter while the device is locked.
@MainActor
struct SecureStorageHandler: NativePlugin {
    var methods: [String: ([String: Any]) throws -> Any] {
    [
        "get": get,
        "set": set,
        "remove": remove,
    ]
}

    private static let service = "ch.stanley.opengym.securestorage"

    func get(_ args: [String: Any]) throws -> Any {
        let key = try args.requiredString("key")
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return ["value": NSNull()] }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw NativeError("keychain read failed (\(status))")
        }
        return ["value": value]
    }

    func set(_ args: [String: Any]) throws -> Any {
        let key = try args.requiredString("key")
        guard let value = args.string("value"),
              let data = value.data(using: .utf8)
        else {
            throw NativeError("keychain write needs a value")
        }

        let query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            let add = SecItemAdd(insert as CFDictionary, nil)
            guard add == errSecSuccess else { throw NativeError("keychain add failed (\(add))") }
        } else if status != errSecSuccess {
            throw NativeError("keychain update failed (\(status))")
        }
        return [:]
    }

    func remove(_ args: [String: Any]) throws -> Any {
        SecItemDelete(baseQuery(try args.requiredString("key")) as CFDictionary)
        return [:]
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
        ]
    }
}

// MARK: - Print

/// Hands a self-contained HTML document to the iOS print sheet — "Save to Files" as PDF, share,
/// or a real printer. Upstream routes the same document through Android's PrintManager from
/// PrintPlugin.java; neither side bundles a PDF library, the OS renders it. Called from
/// lib/mobile.js printHtml(), which lib/plan-share.js feeds the weekly plan.
@MainActor
struct PrintHandler: NativePlugin {
    var methods: [String: ([String: Any]) throws -> Any] {
    [
        "printHtml": printHtml,
    ]
}

    func printHtml(_ args: [String: Any]) throws -> Any {
        let html = try args.requiredString("html")
        let name = args.string("name") ?? "openGym"

        // UIMarkupTextPrintFormatter renders HTML into the print item's own web view, which is
        // how a self-contained document reaches the printer without a second WebView.
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = name

        guard let root = AppDelegate.topViewController() else {
            throw NativeError("no view controller to print from")
        }

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = formatter
        controller.present(animated: true) { _, completed, _ in
            if !completed { controller.dismiss(animated: true) }
        }
        return [:]
    }
}