import Foundation

/// Lifetime keep-awake stats — ported 1:1 from the original Espresso `stats.rs`
/// (dosage levels + milestone thresholds preserved exactly).
struct UptimeStats: Codable {
    var totalSeconds: UInt64 = 0
    var milestonesSeen: [String] = []
}

final class StatsTracker {
    private(set) var stats: UptimeStats
    private var sessionStart: Date?

    private static var fileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Espresso", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stats.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let s = try? JSONDecoder().decode(UptimeStats.self, from: data) {
            stats = s
        } else {
            stats = UptimeStats()
        }
    }

    func startSession() { sessionStart = Date() }

    func endSession() {
        guard let started = sessionStart else { return }
        sessionStart = nil
        stats.totalSeconds += UInt64(max(0, Date().timeIntervalSince(started)))
        let totalHours = stats.totalSeconds / 3600
        for m in Self.checkMilestones(totalHours, seen: stats.milestonesSeen) {
            stats.milestonesSeen.append(m)
        }
        persist()
    }

    /// Total including the in-progress session.
    var liveTotalSeconds: UInt64 {
        var total = stats.totalSeconds
        if let started = sessionStart {
            total += UInt64(max(0, Date().timeIntervalSince(started)))
        }
        return total
    }

    var formattedTotal: String {
        let s = liveTotalSeconds
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var dosageLevel: String {
        switch liveTotalSeconds / 3600 {
        case 0: return "First timer"
        case 1...23: return "Casual user"
        case 24...99: return "Regular dose"
        case 100...499: return "Heavy usage"
        case 500...999: return "Prescription strength"
        default: return "Heroic dose"
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stats) {
            try? data.write(to: Self.fileURL)
        }
    }

    private static func checkMilestones(_ totalHours: UInt64, seen: [String]) -> [String] {
        let milestones: [(UInt64, String)] = [
            (1, "First Hour"), (24, "24 Hours"), (100, "100 Hours"),
            (168, "1 Week"), (500, "500 Hours"), (720, "1 Month"),
            (1000, "1,000 Hours — Seek help"),
        ]
        return milestones
            .filter { totalHours >= $0.0 && !seen.contains($0.1) }
            .map { $0.1 }
    }
}
