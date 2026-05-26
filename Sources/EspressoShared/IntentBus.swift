import Foundation

/// Bridge between the AppIntents (defined here in EspressoShared so
/// both the widget extension and the host can see them) and the
/// running Espresso host process that will actually toggle keep-awake.
///
/// `ToggleEspressoIntent` declares `openAppWhenRun = true`, so when
/// the widget's `Button(intent:)` fires the system wakes / launches
/// Espresso and runs `perform()` in the **host process** — that's
/// where the keep-awake engine lives. The host's `AppDelegate` calls
/// `IntentBus.shared.register(...)` at launch with a closure that
/// drives `EspressoStore`; the AppIntent's `perform()` invokes that
/// closure via the bus. No registered handler (running in the
/// extension by accident, or before the host has finished launching)
/// → silent no-op rather than crash.
@MainActor
public final class IntentBus {
    public static let shared = IntentBus()
    private init() {}

    private var toggleHandler: (@MainActor () -> Void)?

    public func register(toggle: @escaping @MainActor () -> Void) {
        self.toggleHandler = toggle
    }

    public func toggle() { toggleHandler?() }
}
