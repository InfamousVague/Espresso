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

    public override init() {
        super.init()
        store.onStateChange = { [weak self] in
            guard let self else { return }
            self.onMenuBarImageChange?(self.paneMenuBarImage())
        }
        // Subscribing to widget signals lives in paneStart, NOT
        // init: with the launcher's `loadPanes(activate: true)`,
        // paneStart fires at boot, so the subscription happens
        // early enough for the Dynamic Island. Doing it in BOTH
        // places caused a double-fire that toggled the store
        // back to its original state on every signal.
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
