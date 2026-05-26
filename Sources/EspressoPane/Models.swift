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
        clamshellOn = Clamshell.isActive
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
        onStateChange?()
        publishWidgetSnapshot()
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

    /// Panic — instant full stop: simulation + keep-awake + clamshell.
    func panic() {
        if clamshellOn { _ = Clamshell.disable(); clamshellOn = false }
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

    func setClamshell(_ on: Bool) {
        if let err = (on ? Clamshell.enable() : Clamshell.disable()) {
            lastError = err
            clamshellOn = Clamshell.isActive
        } else {
            clamshellOn = on
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
        if let start = sessionStart {
            let e = Int(Date().timeIntervalSince(start))
            let h = e / 3600, m = (e % 3600) / 60, s = e % 60
            awakeElapsed = h > 0 ? "\(h)h \(m)m" : (m > 0 ? "\(m)m \(s)s" : "\(s)s")
        }
        if let end = endDate {
            let secs = Int(end.timeIntervalSinceNow)
            if secs <= 0 { deactivate(); return }
            let h = secs / 3600, m = (secs % 3600) / 60
            remaining = h > 0 ? "\(h)h \(m)m" : "\(m)m \(secs % 60)s"
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
        EspressoSettings(preferredMode: mode, simProfile: simProfile).save()
    }
}
