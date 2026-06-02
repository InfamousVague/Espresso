import Foundation
import Observation
import AppKit
import WidgetKit
import EspressoShared

// MARK: - Timer presets (ported from state.rs / TimerPreset)

enum TimerPreset: String, CaseIterable, Codable, Identifiable {
    case min5, min10, min15, min30, min45, hour1, hour2, hour4, hour8, indefinite
    var id: String { rawValue }

    var label: String {
        switch self {
        case .min5: return "5m"
        case .min10: return "10m"
        case .min15: return "15m"
        case .min30: return "30m"
        case .min45: return "45m"
        case .hour1: return "1h"
        case .hour2: return "2h"
        case .hour4: return "4h"
        case .hour8: return "8h"
        case .indefinite: return "∞"
        }
    }

    var durationSecs: UInt64? {
        switch self {
        case .min5: return 5 * 60
        case .min10: return 10 * 60
        case .min15: return 15 * 60
        case .min30: return 30 * 60
        case .min45: return 45 * 60
        case .hour1: return 3600
        case .hour2: return 2 * 3600
        case .hour4: return 4 * 3600
        case .hour8: return 8 * 3600
        case .indefinite: return nil
        }
    }
}

// MARK: - Mouse-jiggle profiles (ported from profiles.rs)

enum SimProfile: String, CaseIterable, Codable, Identifiable {
    case slack, teams, zoom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var mouse: Bool { true }
    var keyboard: Bool { self == .teams }

    /// (min, max) seconds between simulated actions.
    var intervalRange: ClosedRange<Double> {
        switch self {
        case .slack: return 60...120
        case .teams: return 45...90
        case .zoom: return 30...60
        }
    }
}

// MARK: - Persisted settings

struct EspressoSettings: Codable {
    var preferredMode: AwakeMode = .displayAndSystem
    var simProfile: SimProfile = .slack
    /// User-controlled preference: when true, an active keep-awake
    /// session also flips `pmset disablesleep` so the Mac stays
    /// awake with the lid closed. Off by default; tied to session
    /// lifecycle, not a system-wide always-on switch.
    var clamshellEnabled: Bool = false

    private static var url: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Espresso", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    static func load() -> EspressoSettings {
        (try? JSONDecoder().decode(EspressoSettings.self, from: Data(contentsOf: url))) ?? EspressoSettings()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.url) }
    }
}

// MARK: - Store

@MainActor
@Observable
final class EspressoStore {
    var active = false
    var mode: AwakeMode = .displayAndSystem
    var preset: TimerPreset = .indefinite
    var remaining: String = ""
    var awakeElapsed: String = ""
    var jiggleOn = false
    var simProfile: SimProfile = .slack
    var clamshellOn = false
    var lastError: String?

    /// Set by the app delegate to refresh the menu-bar icon on state change.
    @ObservationIgnored var onStateChange: (() -> Void)?

    @ObservationIgnored private let engine = Awake()
    @ObservationIgnored let stats = StatsTracker()
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var sessionStart: Date?
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var jiggleCancelled = false

    init() {
        let s = EspressoSettings.load()
        mode = s.preferredMode
        simProfile = s.simProfile
        // Setting, not live state — the lid-closed override is now
        // tied to session lifecycle (engaged in activate, released
        // in deactivate), so the toggle persists across launches.
        clamshellOn = s.clamshellEnabled
    }

    // MARK: Activation

    func activate(preset: TimerPreset, mode: AwakeMode) {
        self.preset = preset
        self.mode = mode
        engine.apply(mode)
        active = true
        sessionStart = Date()
        awakeElapsed = "0s"
        stats.startSession()

        // Engage the lid-closed override for the lifetime of this
        // session only — no-op when the user hasn't opted in or
        // when the sudoers rule isn't installed.
        if clamshellOn && Clamshell.sudoersInstalled {
            if let err = Clamshell.enable() { lastError = err }
        }

        if let secs = preset.durationSecs {
            endDate = Date().addingTimeInterval(TimeInterval(secs))
        } else {
            endDate = nil
        }
        startTick()
        if jiggleOn { startJiggle() }
        persist()
        onStateChange?()
        publishWidgetSnapshot()
    }

    func deactivate() {
        engine.release()
        stats.endSession()
        active = false
        endDate = nil
        sessionStart = nil
        remaining = ""
        awakeElapsed = ""
        tickTimer?.invalidate(); tickTimer = nil
        stopJiggle()
        // Always undo any pmset disablesleep we set for this session.
        // Idempotent if we didn't enable it.
        if Clamshell.sudoersInstalled { _ = Clamshell.disable() }
        onStateChange?()
        publishWidgetSnapshot()
    }

    /// Push the session's end time out by `minutes` minutes —
    /// the quick "+15 / +30 / +1h" buttons in Halo's expanded
    /// card call this so the user can extend a keep-awake
    /// without opening the popover.
    ///
    /// If the session is currently indefinite (no `endDate`),
    /// we leave it indefinite — extending "forever" by a few
    /// minutes is meaningless. If the session is fixed, we
    /// bump its end date and refresh the countdown immediately
    /// so the new value shows up in the menu-bar pill and the
    /// island within the same tick.
    func extend(byMinutes minutes: Int) {
        guard active, minutes > 0 else { return }
        if let current = endDate {
            endDate = current.addingTimeInterval(
                TimeInterval(minutes * 60))
            updateRemaining()
            onStateChange?()
            publishWidgetSnapshot()
        }
        // No-op for indefinite sessions — they already run
        // until the user explicitly stops them.
    }

    /// Single-tap toggle from the widget. Activates with the user's
    /// last preferred mode + the indefinite preset (matching what a
    /// user gets by clicking the menu-bar icon with no timer set),
    /// or deactivates if already running. Idempotent on repeated
    /// posts (no-ops if the requested transition is already done) so
    /// the two-track intent dispatch (`IntentBus` + `WidgetSignal`)
    /// can fire both paths without doubling up.
    func toggle() {
        if active {
            deactivate()
        } else {
            activate(preset: .indefinite, mode: mode == .off ? .displayAndSystem : mode)
        }
    }

    /// Panic — instant full stop. deactivate() already releases the
    /// keep-awake assertions, jiggle, and the lid-closed pmset
    /// override; we preserve the user's clamshell preference so the
    /// next session still uses it.
    func panic() {
        deactivate()
    }

    func setMode(_ m: AwakeMode) {
        mode = m
        persist()
        if active { engine.apply(m) }
    }

    // MARK: Jiggle

    func setJiggle(_ on: Bool) {
        jiggleOn = on
        if on {
            if !Jiggle.accessibilityTrusted { Jiggle.promptAccessibility() }
            if active { startJiggle() }
        } else {
            stopJiggle()
        }
    }

    func setSimProfile(_ p: SimProfile) {
        simProfile = p
        persist()
        if active && jiggleOn { stopJiggle(); startJiggle() }
    }

    private func startJiggle() {
        jiggleCancelled = false
        scheduleJiggle()
    }

    private func stopJiggle() { jiggleCancelled = true }

    private func scheduleJiggle() {
        let profile = simProfile
        let delay = Double.random(in: profile.intervalRange)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.jiggleCancelled, self.active, self.jiggleOn else { return }
            DispatchQueue.global(qos: .utility).async {
                Jiggle.perform(mouse: profile.mouse, keyboard: profile.keyboard)
            }
            self.scheduleJiggle()
        }
    }

    // MARK: Clamshell

    /// Flip the lid-closed-override preference. This no longer puts
    /// `pmset disablesleep` into a persistent on-state — it just
    /// records the user's intent. The override is engaged when a
    /// keep-awake session activates and released when it ends.
    ///
    /// On first-time enable, the sudoers rule is installed (one
    /// interactive admin prompt); subsequent toggles are silent.
    func setClamshell(_ on: Bool) {
        if on {
            // First-time setup only — no-op if already installed.
            if !Clamshell.sudoersInstalled, let err = Clamshell.installSudoers() {
                lastError = err
                clamshellOn = false
                persist()
                return
            }
            clamshellOn = true
            persist()
            // If a session is already running, engage now so the
            // change takes effect without waiting for the next start.
            if active, Clamshell.sudoersInstalled,
               let err = Clamshell.enable() {
                lastError = err
            }
        } else {
            clamshellOn = false
            persist()
            // Always release pmset so toggling off mid-session
            // restores normal lid-close sleep immediately.
            if Clamshell.sudoersInstalled { _ = Clamshell.disable() }
        }
    }

    func removeClamshellRule() {
        if Clamshell.isActive { _ = Clamshell.disable() }
        if let e = Clamshell.removeSudoers() { lastError = e }
        clamshellOn = false
    }

    var clamshellSudoersInstalled: Bool { Clamshell.sudoersInstalled }

    // MARK: Tick

    private func startTick() {
        tickTimer?.invalidate()
        updateRemaining()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateRemaining() }
        }
    }

    private func updateRemaining() {
        guard active else { return }
        // Zero-pad every component to two digits so the pill
        // never re-flows mid-countdown. `01h 05m` rolls
        // digit-for-digit into `01h 04m`; without the padding
        // a 1h → 9h transition (or the m→s changeover) shifts
        // the label width every tick.
        if let start = sessionStart {
            let e = Int(Date().timeIntervalSince(start))
            let h = e / 3600, m = (e % 3600) / 60, s = e % 60
            awakeElapsed = h > 0
                ? String(format: "%02dh %02dm", h, m)
                : (m > 0
                    ? String(format: "%02dm %02ds", m, s)
                    : String(format: "%02ds", s))
        }
        if let end = endDate {
            let secs = Int(end.timeIntervalSinceNow)
            if secs <= 0 { deactivate(); return }
            let h = secs / 3600, m = (secs % 3600) / 60
            remaining = h > 0
                ? String(format: "%02dh %02dm", h, m)
                : String(format: "%02dm %02ds", m, secs % 60)
        } else {
            remaining = ""
        }
        // Tick-rate snapshot — keeps the widget's remaining/elapsed
        // strings in step with the panel UI without each ContentView
        // tick needing to know about the widget. `SharedStatsStore`
        // is intentionally not throttled here (cf. Stats which writes
        // at 2 Hz) because Espresso ticks at 1 Hz, well under
        // WidgetKit's internal reload-rate ceiling.
        publishWidgetSnapshot()
    }

    /// Compose + write the widget-facing snapshot, then poke
    /// WidgetKit to reload timelines. Cheap (one tiny JSON write +
    /// one IPC); safe to call from any state-change site.
    func publishWidgetSnapshot() {
        let snapshot = SharedStats(
            active: active,
            modeLabel: mode.label,
            remaining: remaining,
            elapsed: awakeElapsed,
            jiggleOn: jiggleOn,
            clamshellOn: clamshellOn,
            sampledAt: Date()
        )
        StatsStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persist() {
        EspressoSettings(preferredMode: mode, simProfile: simProfile,
                         clamshellEnabled: clamshellOn).save()
    }
}
