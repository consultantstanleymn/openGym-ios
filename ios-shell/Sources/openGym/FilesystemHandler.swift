import Foundation

// Filesystem. The seven methods openGym calls, and nothing else.
//
// Directory names arrive as the strings the JS shim sends (DATA, CACHE, DOCUMENTS, LIBRARY) and
// are resolved here against the app sandbox. The mapping matters in two places:
//
//   DATA -> Library/Application Support/
//     The opengym-state.json mirror. Application Support is the right home for it: iOS excludes
//     it from user-visible storage but keeps it out of the purgeable cache, which is exactly the
//     durability lib/mobile.js needs and cannot get from Caches.
//
//   LIBRARY -> Library/
//     opengym-media/, the user's own photos and videos. This is the folder that is included in
//     iCloud and device backups and excluded from nothing, as upstream's own mobile build does.
//
// Every path is resolved and then checked for containment, because a filename in this app can
// come from a backup import.

@MainActor
struct FilesystemHandler: NativePlugin {

    var methods: [String: ([String: Any]) throws -> Any] {
        ["readFile": readFile,
        "writeFile": writeFile,
        "appendFile": appendFile,
        "deleteFile": deleteFile,
        "deleteDirectory": deleteDirectory,
        "readdir": readdir,
        "mkdir": mkdir,
        "rmdir": rmdir,
        "getUri": getUri,
        "stat": stat,
        "exists": exists,
        ]
    }

    // MARK: - directory resolution

    enum Root: String {
        case documents = "DOCUMENTS"
        case library = "LIBRARY"
        case data = "DATA"
        case cache = "CACHE"

        var url: URL {
            switch self {
            case .documents: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            case .library: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            case .data: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            case .cache: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            }
        }
    }

    /// Resolve (directory, path) to a real file, refusing anything that escapes the root.
    private func url(_ args: [String: Any]) throws -> URL {
        let name = args.string("directory") ?? Root.data.rawValue
        guard let root = Root(rawValue: name) else {
            throw NativeError("unknown directory: \(name)")
        }
        let relative = try args.requiredString("path")
        let rootURL = root.url
        // openGym's media files live under a nested path (Library/opengym-media/...), so the
        // intermediate directories are created on write but a read of a missing one is an error.
        let target = rootURL.appendingPathComponent(relative).standardizedFileURL
        guard target.path.hasPrefix(rootURL.standardizedFileURL.path) else {
            throw NativeError("path escapes \(name)")
        }
        return target
    }

    private func ensureParent(_ file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true)
    }

    // MARK: - methods

    func readFile(_ args: [String: Any]) throws -> Any {
        let file = try url(args)
        let data = try Data(contentsOf: file)
        if args.string("encoding") == "base64" {
            return ["data": data.base64EncodedString(), "uri": file.absoluteString]
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw NativeError("not valid UTF-8: \(file.lastPathComponent)")
        }
        return ["data": text, "uri": file.absoluteString]
    }

    func writeFile(_ args: [String: Any]) throws -> Any {
        let file = try url(args)
        try ensureParent(file)
        // A large binary export arrives base64-encoded; the JS side chunks it at 3 MB
        // (shareExportBlob), so each piece decodes on its own and the first one overwrites.
        let encoding = args.string("encoding")
        let payload = args.string("data") ?? ""
        let bytes: Data = encoding == "base64"
            ? Data(base64Encoded: payload) ?? Data()
            : Data(payload.utf8)
        try bytes.write(to: file, options: .atomic)
        return ["uri": file.absoluteString]
    }

    func appendFile(_ args: [String: Any]) throws -> Any {
        let file = try url(args)
        try ensureParent(file)
        let encoding = args.string("encoding")
        let payload = args.string("data") ?? ""
        let bytes: Data = encoding == "base64"
            ? Data(base64Encoded: payload) ?? Data()
            : Data(payload.utf8)

        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
        } else {
            // First piece of a chunked write never landed — start it rather than dropping data.
            try bytes.write(to: file)
        }
        return [:]
    }

    func deleteFile(_ args: [String: Any]) throws -> Any {
        let file = try url(args)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        return [:]
    }

    func deleteDirectory(_ args: [String: Any]) throws -> Any {
        try remove(try url(args), recursive: args.bool("recursive") ?? true)
        return [:]
    }

    func rmdir(_ args: [String: Any]) throws -> Any {
        try remove(try url(args), recursive: args.bool("recursive") ?? false)
        return [:]
    }

    private func remove(_ target: URL, recursive: Bool) throws {
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        if recursive {
            try FileManager.default.removeItem(at: target)
        } else {
            let items = try FileManager.default.contentsOfDirectory(atPath: target.path)
            guard items.isEmpty else { throw NativeError("directory not empty: \(target.lastPathComponent)") }
            try FileManager.default.removeItem(at: target)
        }
    }

    // Capacitor 4+ returns {name, type} objects; openGym's auto-backup pruner accepts either and
    // uses the type to avoid treating a directory as a stale backup file.
    func readdir(_ args: [String: Any]) throws -> Any {
        let dir = try url(args)
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: dir.path) else {
            return ["files": [String]()]
        }
        let files: [[String: Any]] = names.map { name in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path, isDirectory: &isDir)
            return ["name": name, "type": isDir.boolValue ? "directory" : "file"]
        }
        return ["files": files]
    }

    func mkdir(_ args: [String: Any]) throws -> Any {
        try FileManager.default.createDirectory(
            at: try url(args),
            withIntermediateDirectories: args.bool("recursive") ?? true)
        return [:]
    }

    func getUri(_ args: [String: Any]) throws -> Any {
        ["uri": try url(args).absoluteString]
    }

    func stat(_ args: [String: Any]) throws -> Any {
        let file = try url(args)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path) else {
            throw NativeError("no such file")
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return [
            "size": size,
            "type": "file",
            "lastModified": Int(modified * 1000),
            "uri": file.absoluteString,
        ]
    }

    func exists(_ args: [String: Any]) throws -> Any {
        ["exists": FileManager.default.fileExists(atPath: try url(args).path)]
    }
}