import Foundation
import UIKit

// Shake to screenshot.
//
// Why this exists: `idevicescreenshot` needs a Developer Disk Image mounted on the device, and
// Xcode 27 does not ship one — it fetches them on demand from Apple when a Mac attaches a phone.
// That was checked rather than assumed: the whole 1.9 GB Xcode.xip was decompressed (9.06 GB out
// of its XZ streams) and searched, and `DeveloperDiskImage.dmg` does not occur in it at all. So
// there is no disk image to mount from Linux, and the usual tool cannot work here.
//
// The app can photograph itself instead, and it already does the hard part: UIGraphicsImageRenderer
// renders a WKWebView including its scroll position and video frames. UIFileSharingEnabled is set
// in Info.plist, so whatever it writes to Documents shows up in the Files app and over USB through
// ifuse.
//
// Shake rather than a button, because a button would have to live somewhere in the web UI and
// would be in the way. UIWindow is the right place to intercept it: a WKWebView consumes motion
// events long before they reach the view controller, and the window sees them first.

/// Emits a screenshot. Main-actor, like every other protocol here: it renders a view.
@MainActor
protocol Snapshotting: AnyObject {
    func takeSnapshot(reason: String) -> URL?
}

final class ScreenshotWindow: UIWindow, Snapshotting {

    /// Set by AppDelegate once the view hierarchy exists. Nil-safe: a shake before the web view is
    /// built should do nothing rather than crash.
    weak var snapshotTarget: UIView?

    /// Shake is deliberately uncancellable-free here: one shake, one file. No UI is shown, because
    /// a toast on every shake would be more annoying than the feature is useful, and the file
    /// appearing in Files is its own confirmation.
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else {
            super.motionEnded(motion, with: event)
            return
        }
        _ = takeSnapshot(reason: "shake")
        // NOT forwarded: the web view has no use for a shake, and forwarding would let a page
        // handle it.
    }

    @discardableResult
    func takeSnapshot(reason: String) -> URL? {
        guard let view = snapshotTarget ?? rootViewController?.view else { return nil }

        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        let image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return nil }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screenshots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // A timestamp, not a counter: screenshots are read by eye and sorted by when they were
            // taken. Seconds are enough — a human cannot shake twice in the same second.
            let stamp = Self.stampFormatter.string(from: Date())
            let url = dir.appendingPathComponent("shot-\(stamp).png")
            try data.write(to: url, options: .atomic)
            NSLog("og: snapshot \(url.lastPathComponent) (\(data.count) bytes)")
            return url
        } catch {
            NSLog("og: snapshot FAILED \(error.localizedDescription)")
            return nil
        }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")   // never a locale's calendar
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

// MARK: - from JavaScript
//
// The same capability as a bridge method, so it can be driven from the page as well as from a
// shake. Useful for "save this screen" in a bug report, and it is how this gets exercised without
// someone physically shaking a phone.

extension NativeBridge {
    func installSnapshot(on window: ScreenshotWindow?) {
        let sink = window
        handlers["Snapshot"] = [
            "take": { (args: [String: Any]) in
                let reason = args.string("reason") ?? "bridge"
                guard let url = sink?.takeSnapshot(reason: reason) else {
                    throw NativeError("snapshot failed")
                }
                return ["path": url.path, "name": url.lastPathComponent]
            },
        ]
        plugins["Snapshot"] = SnapshotPlugin()
    }
}

private struct SnapshotPlugin: NativePlugin {
    var methods: [String: ([String: Any]) throws -> Any] { ["take": { _ in [:] }] }
}