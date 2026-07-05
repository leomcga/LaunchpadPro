import AppKit

enum AppScanner {
    private struct ScanRoot {
        let url: URL
        let maxDepth: Int
    }

    private static let roots: [ScanRoot] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ScanRoot(url: URL(fileURLWithPath: "/Applications", isDirectory: true), maxDepth: 2),
            ScanRoot(url: URL(fileURLWithPath: "/System/Applications", isDirectory: true), maxDepth: 2),
            ScanRoot(url: URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true), maxDepth: 2),
            ScanRoot(url: URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications", isDirectory: true), maxDepth: 2),
            ScanRoot(url: home.appendingPathComponent("Applications", isDirectory: true), maxDepth: 2),
            ScanRoot(url: home.appendingPathComponent("Downloads", isDirectory: true), maxDepth: 2),
            ScanRoot(url: home.appendingPathComponent("Desktop", isDirectory: true), maxDepth: 2)
        ]
    }()

    static var watchedDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true)
        ]
    }

    static func scan() -> [AppRecord] {
        var records: [AppRecord] = []
        var seenPaths = Set<String>()

        for root in roots {
            guard let children = FileManager.default.enumerator(
                at: root.url,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in children {
                let depth = depth(of: url, relativeTo: root.url)
                if depth > root.maxDepth {
                    children.skipDescendants()
                    continue
                }

                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                let isPackage = values?.isPackage ?? false
                let isDirectory = values?.isDirectory ?? false

                guard url.pathExtension == "app", isDirectory else {
                    if isPackage { children.skipDescendants() }
                    continue
                }

                let path = url.path
                guard !seenPaths.contains(path), let record = makeRecord(url) else { continue }
                seenPaths.insert(path)
                records.append(record)
                children.skipDescendants()
            }
        }

        var seenBundles = Set<String>()
        var deduped: [AppRecord] = []
        for record in records {
            if let bundleID = record.bundleIdentifier, !bundleID.isEmpty {
                guard !seenBundles.contains(bundleID) else { continue }
                seenBundles.insert(bundleID)
            }
            deduped.append(record)
        }

        return deduped.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func makeRecord(_ url: URL) -> AppRecord? {
        let bundle = Bundle(url: url)
        let displayName = localizedName(bundle: bundle, url: url, fallback: url.deletingPathExtension().lastPathComponent)
        let values = try? url.resourceValues(forKeys: [.creationDateKey])

        return AppRecord(
            id: url.path,
            name: displayName,
            originalName: displayName,
            path: url.path,
            bundleIdentifier: bundle?.bundleIdentifier,
            dateAdded: values?.creationDate?.timeIntervalSince1970 ?? 0
        )
    }

    private static func depth(of url: URL, relativeTo root: URL) -> Int {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return max(0, components.count - rootComponents.count)
    }

    private static func localizedName(bundle: Bundle?, url: URL, fallback: String) -> String {
        if let localized = localizedInfoPlistName(bundleURL: url) {
            return localized
        }
        if let localized = localizedInfoDictionaryName(bundle: bundle) {
            return localized
        }
        let finderName = FileManager.default.displayName(atPath: url.path)
        if !finderName.isEmpty, finderName != url.lastPathComponent {
            return finderName.replacingOccurrences(of: ".app", with: "")
        }
        if let display = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !display.isEmpty {
            return display
        }
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return fallback
    }

    private static func localizedInfoDictionaryName(bundle: Bundle?) -> String? {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let value = bundle?.localizedString(forKey: key, value: nil, table: "InfoPlist"),
               !value.isEmpty,
               value != key {
                return value
            }
        }
        return nil
    }

    private static func localizedInfoPlistName(bundleURL: URL) -> String? {
        let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let preferred = Locale.preferredLanguages.flatMap { languageCandidates(for: $0) }
        let fallbacks = ["zh-Hans", "zh_CN", "zh-Hans-CN", "zh", "Base", "en"]
        var seen = Set<String>()

        for language in preferred + fallbacks where seen.insert(language).inserted {
            let url = resources
                .appendingPathComponent(language + ".lproj", isDirectory: true)
                .appendingPathComponent("InfoPlist.strings")
            guard let values = NSDictionary(contentsOf: url) as? [String: String] else { continue }
            if let display = values["CFBundleDisplayName"], !display.isEmpty {
                return display
            }
            if let name = values["CFBundleName"], !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private static func languageCandidates(for identifier: String) -> [String] {
        var result = [identifier]
        let normalized = identifier.replacingOccurrences(of: "-", with: "_")
        result.append(normalized)

        if normalized.hasPrefix("zh_Hans") {
            result.append(contentsOf: ["zh_CN", "zh-Hans", "zh"])
        } else if normalized.hasPrefix("zh_Hant") {
            result.append(contentsOf: ["zh_TW", "zh-Hant", "zh"])
        } else if let base = normalized.split(separator: "_").first {
            result.append(String(base))
        }

        return result
    }

    static func icon(for app: AppRecord) -> NSImage {
        IconStore.shared.icon(path: app.path)
    }
}

final class IconStore {
    static let shared = IconStore()

    private var icons: [String: NSImage] = [:]
    private let lock = NSLock()

    func icon(path: String) -> NSImage {
        lock.lock()
        defer { lock.unlock() }

        if let image = icons[path] { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 128, height: 128)
        icons[path] = image
        return image
    }
}
