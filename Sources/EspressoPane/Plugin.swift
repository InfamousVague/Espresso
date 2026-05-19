import AppKit
import SwiftUI
import SuiteKit

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
    }

    public func paneStop() {
        // Espresso holds no poll timer at rest (timers only run while
        // active); the panic hotkey is harmless to leave registered.
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
