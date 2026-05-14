import Foundation

/// Single source of truth for every path inside the iCloud container.
///
/// Identifier format note: this constant uses the dotted form, which is
/// what `FileManager.url(forUbiquityContainerIdentifier:)` expects. The
/// on-disk path the Mac sees uses tildes
/// (`~/Library/Mobile Documents/iCloud~com~jlgao~PrefrontalCortex/`).
/// Both refer to the same container.
enum iCloudPaths {
    static let containerId = "iCloud.com.jlgao.PrefrontalCortex"

    /// Returns the container's `Documents` root. nil when:
    ///   - the user isn't signed into iCloud,
    ///   - the entitlement is missing,
    ///   - the container hasn't been provisioned yet (typically on
    ///     first launch — provisioning takes seconds after install).
    static var root: URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: containerId)?
            .appendingPathComponent("Documents")
    }

    static var inboxDir:    URL? { root?.appendingPathComponent("inbox") }
    static var outboxDir:   URL? { root?.appendingPathComponent("outbox") }
    static var configDir:   URL? { root?.appendingPathComponent("config") }
    static var cacheDir:    URL? { root?.appendingPathComponent("cache") }
    static var backupsDir:  URL? { root?.appendingPathComponent("backups") }

    static var bundleURL:   URL? { outboxDir?.appendingPathComponent("ios_bundle.json") }
    static var manifestURL: URL? { outboxDir?.appendingPathComponent("manifest.json") }

    static var healthProfileURL:   URL? { configDir?.appendingPathComponent("health_profile.json") }
    static var exerciseLibraryURL: URL? { configDir?.appendingPathComponent("exercise_library.json") }

    /// Path for a user-edited config file, e.g. "weekly_rhythm.json".
    /// The laptop pipeline reads files in `config/` to influence its
    /// bundle output, so iOS-side edits (rhythm, swaps, custom slots)
    /// land here as `<name>.json` and the pipeline picks them up on
    /// the next refresh.
    static func configFile(name: String) -> URL? {
        configDir?.appendingPathComponent("\(name).json")
    }

    static func inboxFile(kind: String, date: Date) -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return inboxDir?.appendingPathComponent("\(kind)_\(f.string(from: date)).json")
    }

    /// True iff the container root is currently reachable.
    static var isAvailable: Bool { root != nil }
}
