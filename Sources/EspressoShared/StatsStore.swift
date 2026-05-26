import Foundation

/// Reads/writes `SharedStats` to a location both the host and the
/// widget extension can reach.
///
/// Primary location: the App Group container at
/// `~/Library/Group Containers/<AppGroup.id>/espresso-stats.json`,
/// resolved via `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
/// That requires the signed bundle to carry the App Group
/// entitlement — when it doesn't (e.g., `swift run` from the
/// command line), the call returns `nil` and we fall back to the
/// host-only Application Support path so dev iteration still works,
/// just not visible to the widget extension.
public enum StatsStore {
    private static let filename = "espresso-stats.json"

    /// Resolved write/read path. Group Container when entitled,
    /// else the host's Application Support dir as a dev fallback.
    public static func storeURL() -> URL {
        let fm = FileManager.default
        if let g = fm.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.id
        ) {
            return g.appendingPathComponent(filename)
        }
        let support = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser
        let dir = support.appendingPathComponent("com.mattssoftware.espresso")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    /// Returns `nil` if no payload yet, or the on-disk file is from
    /// a future Espresso whose schema we don't recognise (defensive —
    /// an old widget reading a newer host's blob shows the
    /// placeholder rather than crashing on decode).
    public static func read() -> SharedStats? {
        let url = storeURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        // MUST match write()'s `.iso8601` strategy — the default
        // `.deferredToDate` expects a Double timestamp, so reading
        // the writer's ISO-8601 string would fail the whole decode
        // and the widget would silently fall back to its empty
        // placeholder. Spent an embarrassing amount of time on this
        // exact mismatch in Alfred; not making it here.
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let s = try? dec.decode(SharedStats.self, from: data)
        else { return nil }
        guard s.version <= SharedStats.currentVersion else { return nil }
        return s
    }

    /// Atomic write — the widget's TimelineProvider may be reading
    /// the file at any moment.
    public static func write(_ stats: SharedStats) {
        let url = storeURL()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(stats) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
