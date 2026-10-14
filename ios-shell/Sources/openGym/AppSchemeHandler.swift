import Foundation
import WebKit

// Serves the web bundle over app:// instead of file://.
//
// This is the load-bearing decision in the whole shell. A WKWebView loaded from file:// runs in
// an opaque origin, and an opaque origin gets no localStorage at all — no quota, no persistence,
// and every read after the first throws. openGym keeps its entire state in localStorage (the
// Zustand store, the routines, the workout history), so on file:// the app would look like it
// worked and then lose everything the moment it was backgrounded. lib/mobile.js mirrors each save
// to a JSON file precisely because iOS evicts WebView storage, but that mirror is a recovery
// path, not a substitute for an origin that has storage in the first place.
//
// A custom scheme registered with WKURLSchemeHandler gets a real, consistent origin that survives
// across launches. Every asset path in the bundle is relative (vite.config.js sets base: './'), so
// they resolve against app://openGym.local/ without rewriting anything.

@MainActor
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {

    /// Where the built bundle landed inside the app. Package.swift declares WebBundle as a
    /// resource, so SwiftPM's accessor is used rather than a hardcoded path.
    ///
    /// Optional, and deliberately not force-unwrapped: the directory is created by
    /// scripts/build-web.sh, so a shell built without that step should say so plainly rather than
    /// crash on launch. `serve` turns nil into that message.
    static let bundleURL: URL? = Bundle.module.url(forResource: "WebBundle", withExtension: nil)

    static let scheme = "app"
    static let host = "openGym.local"

    private var task = WebViewTask()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard urlSchemeTask.request.url?.scheme == Self.scheme else {
            urlSchemeTask.didFailWithError(NativeError("unsupported scheme"))
            return
        }
        serve(urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        task.cancel(urlSchemeTask)
    }

    private func serve(_ task: WKURLSchemeTask) {
        guard let bundle = Self.bundleURL else {
            task.didFailWithError(NativeError(
                "WebBundle is missing from the app. Run scripts/build-web.sh before xtool dev."))
            return
        }
        guard let url = task.request.url else {
            task.didFailWithError(NativeError("no url"))
            return
        }

        // Path traversal guard. The bundle is ours and nothing should ever ask for ../.., but this
        // is the one handler in the app that turns a URL into a file read, so the containment
        // check lives here rather than being assumed.
        let relative = Self.relativePath(url)
        let target = bundle.appendingPathComponent(relative)

        guard Self.isContained(target, in: bundle) else {
            task.didFailWithError(NativeError("path escapes the bundle"))
            return
        }

        guard let data = try? Data(contentsOf: target, options: .mappedIfSafe) else {
            task.didFailWithError(NativeError("not found in bundle: \(relative)"))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: relative),
                // The whole app is a snapshot shipped inside the app; nothing should be cached
                // across a reinstall, and a stale chunk after an update is worse than a re-read.
                "Cache-Control": "no-cache",
                "Content-Length": "\(data.count)",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    // MARK: - path handling

    private static func relativePath(_ url: URL) -> String {
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "index.html" }
        // Percent-decoding: the scheme handler is handed the URL as WebKit parsed it, and an
        // exercise media path like /exercise-media/still/0001.webp arrives encoded.
        return path.removingPercentEncoding ?? path
    }

    private static func isContained(_ target: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
    }

    // A short table rather than a dependency: the bundle is HTML, JS, CSS, JSON, WebP and MP4.
    // Anything unrecognised is served as application/octet-stream, which is what a download
    // should look like anyway.
    private static func mimeType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "webmanifest": return "application/manifest+json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "jpg", "jpeg": return "image/jpeg"
        case "mp4": return "video/mp4"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "md": return "text/markdown; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}

/// Tracks in-flight scheme tasks so `stop` can cancel them. WebKit calls stop when a navigation is
/// superseded; a task that is already finished must not be finished again.
private final class WebViewTask {
    private var live = Set<ObjectIdentifier>()

    func finish(_ task: WKURLSchemeTask, after block: () -> Void) {
        live.insert(ObjectIdentifier(task))
        block()
        live.remove(ObjectIdentifier(task))
    }

    func cancel(_ task: WKURLSchemeTask) {
        live.remove(ObjectIdentifier(task))
    }
}