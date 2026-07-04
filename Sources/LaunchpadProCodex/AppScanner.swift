import AppKit

enum AppScanner {
    static let roots: [URL] = {
        var values = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true)
        ]
        values.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true))
        return values
    }()

    static func scan() -> [AppRecord] {
        var records: [AppRecord] = []
        var seenPaths = Set<String>()

        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in children where url.pathExtension == "app" {
                let path = url.path
                guard !seenPaths.contains(path), let record = makeRecord(url) else { continue }
                seenPaths.insert(path)
                records.append(record)
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
