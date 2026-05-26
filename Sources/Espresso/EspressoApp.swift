import SwiftUI
import AppKit
import EspressoPane
import EspressoShared
import SuiteKit

// Standalone Espresso. After the SuiteKit split this file is just a
// host shim: the entire feature (store, UI, keep-awake engine, panic
// hotkey) lives in the `EspressoPane` dynamic library so the
// MattsSoftware launcher can load the very same code out of an
// installed Espresso.app. Behaviour here is identical to the
// pre-split app — its own NSStatusItem + transient NSPopover, the
// idle⇄active cup glyph, edge clamping, click-off close.
@main
struct EspressoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let pane = EspressoPaneProvider()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the IntentBus handler BEFORE SuiteGuard checks for
        // deferral. The widget's `ToggleEspressoIntent` declares
        // `openAppWhenRun = true`, so the system launches us and
        // dispatches `perform()` shortly after this method returns;
        // if we hard-exit via SuiteGuard first, the intent fires
        // into a dead process. Registering up front keeps the bus
        // wired for the brief window the intent needs.
        IntentBus.shared.register(
            toggle: { [weak self] in self?.pane.paneToggle() }
        )

        // If the user set Espresso to "merged" and the MattsSoftware
        // launcher is running, it hosts Espresso's pane — stand down
        // so there's no duplicate menu-bar icon. (No-op standalone.)
        SuiteGuard.exitIfDeferring("espresso")

        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = pane.paneMenuBarImage()
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        pane.onMenuBarImageChange = { [weak self] img in
            self?.statusItem.button?.image = img
        }

        let vc = NSViewController()
        vc.view = pane.paneMakeView()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = vc

        pane.paneStart()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let win = popover.contentViewController?.view.window {
                clampOnScreen(win, anchoredTo: button)
                win.makeKey()
            }
            NSApp.activate(ignoringOtherApps: true)
            if let m = clickMonitor { NSEvent.removeMonitor(m) }
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
    }

    /// Keep the popover fully on the screen that holds the status
    /// item. NSPopover centers on the icon and clips when the icon
    /// is near a screen edge; shift the window back inside.
    private func clampOnScreen(_ win: NSWindow, anchoredTo anchor: NSView) {
        guard let screen = anchor.window?.screen ?? NSScreen.main
        else { return }
        let vis = screen.visibleFrame
        let pad: CGFloat = 8
        var f = win.frame
        if f.maxX > vis.maxX - pad { f.origin.x = vis.maxX - pad - f.width }
        if f.minX < vis.minX + pad { f.origin.x = vis.minX + pad }
        if f.minY < vis.minY + pad { f.origin.y = vis.minY + pad }
        if f != win.frame { win.setFrame(f, display: true) }
    }

    func popoverDidClose(_ notification: Notification) {
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
    }
}
