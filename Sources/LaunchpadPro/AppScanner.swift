import AppKit

/// Discovers installed applications from the standard macOS locations.
enum AppScanner {

    static let searchPaths: [String] = {
        var paths = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Utilities",
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append(home + "/Applications")
        return paths
    }()

    /// Returns every `.app` found, de-duplicated by bundle id / path.
    static func scan() -> [AppItem] {
        let fm = FileManager.default
        var seenPaths = Set<String>()
        var items: [AppItem] = []

        for root in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let fullPath = root + "/" + entry
                if seenPaths.contains(fullPath) { continue }
                seenPaths.insert(fullPath)
                if let item = makeItem(path: fullPath) {
                    items.append(item)
                }
            }
        }

        // De-duplicate apps that appear in more than one place by bundle id,
        // keeping the first (preferring /Applications ordering above).
        var seenBundles = Set<String>()
        var deduped: [AppItem] = []
        for item in items {
            if let bid = item.bundleID {
                if seenBundles.contains(bid) { continue }
                seenBundles.insert(bid)
            }
            deduped.append(item)
        }

        return deduped.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func makeItem(path: String) -> AppItem? {
        let url = URL(fileURLWithPath: path)
        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier

        // Prefer the localized display name, then bundle name, then file name.
        let displayName: String = {
            if let n = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !n.isEmpty { return n }
            if let n = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String, !n.isEmpty { return n }
            return url.deletingPathExtension().lastPathComponent
        }()

        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let created = (attrs?[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0

        return AppItem(
            id: path,
            name: displayName,
            originalName: displayName,
            path: path,
            bundleID: bundleID,
            dateAdded: created
        )
    }

    /// Loads (and caches) the icon for an app.
    static func icon(for item: AppItem) -> NSImage {
        IconCache.shared.icon(forPath: item.path)
    }
}

/// Small in-memory icon cache so we don't repeatedly hit the workspace.
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    func icon(forPath path: String) -> NSImage {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 128, height: 128)
        cache[path] = image
        return image
    }
}
