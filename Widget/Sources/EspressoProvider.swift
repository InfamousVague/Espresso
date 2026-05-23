import WidgetKit
import EspressoShared
import Foundation

/// One timeline entry — what gets handed to the SwiftUI view at each
/// refresh.
struct EspressoEntry: TimelineEntry {
    let date: Date
    let stats: SharedStats
    /// True if the host hasn't ticked in a while; the widget badges
    /// itself "stale" so the user can tell the numbers may have
    /// drifted. ~30 s is generous since Espresso only ticks during
    /// active sessions and the snapshot at deactivate latches the
    /// last value.
    var isStale: Bool {
        guard stats.active else { return false }
        return Date().timeIntervalSince(stats.sampledAt) > 30
    }
}

struct EspressoProvider: TimelineProvider {
    func placeholder(in context: Context) -> EspressoEntry {
        EspressoEntry(date: Date(), stats: .placeholder)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (EspressoEntry) -> Void) {
        let s = StatsStore.read() ?? .placeholder
        completion(EspressoEntry(date: Date(), stats: s))
    }

    /// Timeline. One current entry, refreshed every 30 s as a safety
    /// net — the host calls `WidgetCenter.reloadAllTimelines()`
    /// whenever it actually has new state (every Espresso tick + every
    /// activate/deactivate / jiggle / clamshell change), so the
    /// heartbeat almost never matters.
    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<EspressoEntry>) -> Void) {
        let s = StatsStore.read() ?? .placeholder
        let entry = EspressoEntry(date: Date(), stats: s)
        let next = Date().addingTimeInterval(30)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
