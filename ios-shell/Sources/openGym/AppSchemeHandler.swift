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

    static let scheme = "app"
    static let host = "openGym.local"

    /// Where the built bundle is, found at launch rather than through Bundle.module alone.
    ///
    /// Package.swift declares WebBundle as a resource, so SwiftPM emits `Bundle.module` and the
    /// compiled output lands in `openGym.app/openGym_openGym.bundle/WebBundle`. Bundle.module is
    /// generated for a library product and probes a handful of relative locations; xtool links
    /// that library into the app rather than embedding a framework, so which probe succeeds is
    /// not obvious from the SwiftPM side. Rather than depend on it, every plausible location is
    /// checked once, at launch, and the first one holding index.html wins. `bundleURL` is nil only
    /// when the app was built without running scripts/build-web.sh.
    static let bundleURL: URL? = locateBundle()

    /// SwiftPM names the resource bundle `<package>_<target>.bundle`.
    private static let resourceBundleName = "openGym_openGym.bundle"

    private static func locateBundle() -> URL? {
        var candidates: [URL?] = [
            // Bundle.module's own answer, tried first because it is right when it works.
            Bundle.module.url(forResource: "WebBundle", withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName)
                .appendingPathComponent("WebBundle"),
            Bundle.main.resourceURL?.appendingPathComponent("WebBundle"),
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName)
                .appendingPathComponent("WebBundle"),
            Bundle.main.bundleURL.appendingPathComponent("WebBundle"),
        ]

        for candidate in candidates {
            guard let url = candidate,
                  FileManager.default.fileExists(
                    atPath: url.appendingPathComponent("index.html").path)
            else { continue }
            NSLog("og: bundle at \(url.path)")
            return url
        }

        // Nothing matched. Say exactly where we looked: on a 70 MB app this is the difference
        // between "the web view is broken" and "build-web.sh never ran", and the device console
        // is not readable from here.
        let tried = candidates.compactMap { $0?.path }.joined(separator: "\n    ")
        NSLog("og: BUNDLE NOT FOUND. Tried:\n    \(tried)")
        return nil
    }

    /// Set once at launch so a failure page can name the real reason.
    private(set) static var failureReason: String?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard urlSchemeTask.request.url?.scheme == Self.scheme else {
            urlSchemeTask.didFailWithError(NativeError("unsupported scheme"))
            return
        }
        NSLog("og: scheme request \(urlSchemeTask.request.url?.absoluteString ?? "?")")
        serve(urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to unwind: every path in serve() replies synchronously, so there is no
        // in-flight work left to cancel by the time WebKit calls stop.
    }

    private func serve(_ task: WKURLSchemeTask) {
        guard let bundle = Self.bundleURL else {
            let reason = Self.failureReason ?? "WebBundle is missing from the app."
            NSLog("og: serving failure page: \(reason)")
            return Self.reply(task, html: Self.failurePage(reason), status: 500)
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
            NSLog("og: REJECT \(relative) — escapes the bundle")
            task.didFailWithError(NativeError("path escapes the bundle"))
            return
        }

        guard let data = try? Data(contentsOf: target, options: .mappedIfSafe) else {
            NSLog("og: MISS \(relative)")
            // A missing file is a 404, not a dead app: the page reports it and the rest of the
            // bundle keeps working.
            return Self.reply(task, html: Self.failurePage("not found in bundle: \(relative)"), status: 404)
        }

        NSLog("og: HIT \(relative) (\(data.count) bytes)")
        return Self.reply(
            task,
            data: data,
            type: Self.mimeType(for: relative),
            status: 200)
    }

    // MARK: - responses

    private static func reply(_ task: WKURLSchemeTask, html: String, status: Int) {
        reply(task, data: Data(html.utf8), type: "text/html; charset=utf-8", status: status)
    }

    private static func reply(_ task: WKURLSchemeTask, data: Data, type: String, status: Int) {
        guard let url = task.request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": type,
                    // The whole app is a snapshot shipped inside the app; nothing should be
                    // cached across a reinstall, and a stale chunk after an update is worse.
                    "Cache-Control": "no-cache",
                    "Content-Length": "\(data.count)",
                ])
        else {
            task.didFailWithError(NativeError("could not build response"))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// A readable page instead of a blank screen.
    ///
    /// The device console cannot be read from here — no Developer Disk Image, so no screenshot,
    /// and iOS 27 does not carry app stdout into idevicesyslog. A failure that renders as an
    /// explanation is therefore the only diagnostic available, so every failure path returns one.
    private static func failurePage(_ reason: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>openGym</title>
        <style>
          html,body{margin:0;height:100%;background:#0c0e12;color:#e6e8ee;
            font:15px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
          body{display:flex;align-items:center;justify-content:center;padding:24px}
          div{max-width:520px}
          h1{font-size:17px;margin:0 0 12px;color:#ff6b6b}
          p{margin:0 0 12px}
          pre{background:#151922;border:1px solid #262d3a;border-radius:10px;padding:12px;
            overflow:auto;white-space:pre-wrap;word-break:break-word;font-size:13px;color:#a3e635}
          .muted{color:#8b93a7;font-size:13px}
        </style></head>
        <body><div>
          <h1>The web bundle did not load</h1>
          <p>This is a build problem, not a network one. Nothing here talks to a server.</p>
          <pre>\(reason)</pre>
          <p class="muted">Rebuild from the repository root:<br>bash scripts/build-web.sh</p>
        </div></body></html>
        """
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

    func cancel(_ task: WKURLSchemeTask) {
        live.remove(ObjectIdentifier(task))
    }
}