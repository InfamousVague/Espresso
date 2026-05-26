import AppKit
import SwiftUI
import SuiteKit
import EspressoShared

/// Espresso as a SuiteKit pane. Owns the store, vends the SwiftUI UI
/// and the menu-bar glyph, and drives the idle⇄active icon swap.
/// Both the standalone `@main` shim and the MattsSoftware host talk
/// to Espresso exclusively through this object.
@MainActor
public final class EspressoPaneProvider: NSObject, SuitePane {
    private let store = EspressoStore()

    /// Standalone shim / host segment: called whenever the menu-bar
    /// glyph should change (Espresso swaps cup⇄cup.fill on activate).
    public var onMenuBarImageChange: ((NSImage) -> Void)?

    /// 1 Hz timer that re-publishes the live-activity payload to
    /// the shared store so Halo's countdown stays fresh. Only
    /// runs while the keep-awake session is active — paused
    /// otherwise so we're not writing files for nothing.
    private var publishTimer: Timer?

    public override init() {
        super.init()
        store.onStateChange = { [weak self] in
            guard let self else { return }
            self.onMenuBarImageChange?(self.paneMenuBarImage())
            // Halo (the suite's Dynamic Island agent) reads
            // ~/Library/Application Support/MattsSoftware/
            // live-activity/espresso.json to know when to show
            // our pill. We write here on every state change so
            // the cross-process bridge stays live regardless of
            // whether Halo is also running in the same process
            // tree.
            self.publishLiveActivity()
        }
        // Subscribing to widget signals lives in paneStart, NOT
        // init: with the launcher's `loadPanes(activate: true)`,
        // paneStart fires at boot, so the subscription happens
        // early enough for the Dynamic Island. Doing it in BOTH
        // places caused a double-fire that toggled the store
        // back to its original state on every signal.
    }

    /// Push the current store state to the shared-store JSON file.
    /// ALWAYS publishes — idle is a low-priority "OFF" pill,
    /// active is a higher-priority countdown. That way Espresso
    /// is visible in the island as ambient presence, and
    /// toggling keep-awake on flashes it to focus via Halo's
    /// change-detection.
    private func publishLiveActivity() {
        let symbol: String
        let text: String
        let priority: Int
        if store.active {
            symbol = "cup.and.saucer.fill"
            text = store.remaining.isEmpty ? "ON" : store.remaining
            priority = 60  // above ambient, below transient HUDs
        } else {
            symbol = "cup.and.saucer"
            text = "OFF"
            priority = 25  // ambient — Worktree (50) wins ties
        }
        let payload = SuiteLiveActivityStore.Payload(
            compactLeadingSymbol: symbol,
            compactTrailingText: text,
            tintHex: paneTintHex,
            priority: priority)
        try? SuiteLiveActivityStore.write(payload, for: paneID)
        ensurePublishTimerRunning()
    }

    /// Keep republishing on a timer so Halo's 30s TTL never
    /// drops us. Fast cadence (1s) while active so countdown
    /// text stays fresh; slow cadence (10s) when idle — just
    /// a heartbeat, no UI churn.
    private func ensurePublishTimerRunning() {
        let desired: TimeInterval = store.active ? 1.0 : 10.0
        // No-op if we're already on the right cadence.
        if let t = publishTimer, t.timeInterval == desired {
            return
        }
        publishTimer?.invalidate()
        publishTimer = Timer.scheduledTimer(
            withTimeInterval: desired, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.publishLiveActivity() }
        }
    }

    // MARK: SuitePane

    public var suiteABIVersion: Int { SuiteKitABI.current }
    public var paneID: String { "espresso" }
    public var paneTitle: String { "ESPRESSO" }
    public var paneTintHex: String { "#CD9E6B" }   // crema

    public func paneMenuBarImage() -> NSImage {
        let name = store.active ? "cup.and.saucer.fill" : "cup.and.saucer"
        let img = NSImage(systemSymbolName: name,
                          accessibilityDescription: "Espresso") ?? NSImage()
        img.isTemplate = true
        return img
    }

    public func paneMakeView() -> NSView {
        NSHostingView(rootView: ContentView().environment(store))
    }

    public func paneStart() {
        PanicHotkey.shared.onTrigger = { [weak store] in store?.panic() }
        PanicHotkey.shared.register()

        // Write the initial widget snapshot so the timeline doesn't
        // have to render the placeholder on cold start. After this
        // every state change in the store re-publishes.
        store.publishWidgetSnapshot()

        // Widget button → Darwin notification → pane. Wired here (in
        // addition to the standalone host's `IntentBus.register`) so
        // when the MattsSoftware launcher is hosting Espresso's pane
        // and `SuiteGuard` has exited `Espresso.app`, the launcher's
        // long-lived process still responds.
        subscribeToWidgetSignal(.toggle) { [weak store] in
            store?.toggle()
        }
    }

    public func paneStop() {
        // Espresso holds no poll timer at rest (timers only run while
        // active); the panic hotkey is harmless to leave registered.
    }

    /// Widget intent entry point. Standalone Espresso registers an
    /// `IntentBus` closure that calls this; the launcher-hosted pane
    /// reaches the same `store.toggle()` via the Darwin notification
    /// subscription set up in `paneStart()` above. Two paths, one
    /// result.
    public func paneToggle() { store.toggle() }

    /// Dynamic Island live activity. When Espresso is keeping the
    /// Mac awake the launcher renders a small cup glyph + the
    /// remaining time next to the notch. Returning nil means
    /// "nothing live to show" — the pill drops off the bar
    /// automatically once the keep-awake ends. Polled at ~1 Hz.
    public func paneLiveActivity() -> SuiteLiveActivity? {
        guard store.active else { return nil }
        let cup = NSImage(systemSymbolName: "cup.and.saucer.fill",
                          accessibilityDescription: "Espresso")
        cup?.isTemplate = true
        // Indefinite preset has no countdown string; show a short
        // "ON" label so the pill still reads as an active state.
        let text = store.remaining.isEmpty ? "ON" : store.remaining
        let expanded = NSHostingView(rootView: EspressoLiveActivityExpanded(
            store: store,
            tintHex: paneTintHex
        ))
        return SuiteLiveActivity(
            compactLeadingImage: cup,
            compactTrailingText: text,
            compactTrailingImage: nil,
            tintHex: paneTintHex,
            priority: 60,            // time-bounded band
            expandedView: expanded
        )
    }
}

/// Expanded-state UI hosted inside the launcher's pill. Small
/// surface — just enough to tell the user what's keeping the Mac
/// awake and give them a one-tap escape.
@MainActor
private struct EspressoLiveActivityExpanded: View {
    let store: EspressoStore
    let tintHex: String

    private var tint: Color {
        var s = tintHex
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt32(s, radix: 16) else { return .white }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Espresso")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(store.remaining.isEmpty
                         ? "Keeping awake"
                         : "Awake for \(store.remaining)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button {
                    store.panic()
                } label: {
                    Text("Stop")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// SuiteKit discovery symbol — the host `dlopen`s this framework and
/// `dlsym`s `suitePaneCreate`. The host always calls it on the main
/// thread, which is why assuming main-actor isolation here is safe.
@_cdecl("suitePaneCreate")
public func suitePaneCreate() -> Unmanaged<AnyObject> {
    MainActor.assumeIsolated {
        Unmanaged.passRetained(EspressoPaneProvider())
    }
}
