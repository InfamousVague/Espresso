import Foundation

/// Darwin-notification bridge between the widget extension and the
/// running Espresso pane (standalone `Espresso.app` or the
/// MattsSoftware launcher's hosted `EspressoPane`).
///
/// Why a second signal path alongside `IntentBus`? `IntentBus` is a
/// per-process singleton; its closures only fire in the SAME process
/// that registered them. `openAppWhenRun = true` covers most cases
/// by launching Espresso to run `perform()`, but when the launcher
/// is hosting Espresso, `SuiteGuard.exitIfDeferring("espresso")`
/// exits `Espresso.app` in its first millisecond and the intent
/// would fire into a dead process. Darwin notifications cross
/// sandbox + process boundaries, so the long-lived listener (the
/// launcher's hosted pane) reacts regardless. Two-track dispatch,
/// same pattern as Alfred.
public enum WidgetSignal: String, Sendable {
    case toggle = "com.mattssoftware.espresso.widget.toggle"

    /// Post this signal. Safe to call from any process / sandbox.
    public func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(rawValue as CFString),
            nil, nil, true
        )
    }
}

/// Holds the Swift closure across the C-callback boundary the Darwin
/// notification API uses.
private final class _SignalObserver {
    let handler: () -> Void
    init(_ h: @escaping () -> Void) { handler = h }
}

/// Subscribe to a `WidgetSignal`. Handler hops to the main actor.
/// Returns an opaque token — Darwin observers are process-scoped, so
/// dropping it doesn't unsubscribe (which is what we want).
@discardableResult
@MainActor
public func subscribeToWidgetSignal(
    _ signal: WidgetSignal,
    _ handler: @escaping @MainActor () -> Void
) -> AnyObject {
    let observer = _SignalObserver {
        Task { @MainActor in handler() }
    }
    let opaque = Unmanaged.passRetained(observer).toOpaque()
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        opaque,
        { _, observerPtr, _, _, _ in
            guard let observerPtr else { return }
            let obs = Unmanaged<_SignalObserver>
                .fromOpaque(observerPtr).takeUnretainedValue()
            obs.handler()
        },
        signal.rawValue as CFString,
        nil,
        .deliverImmediately
    )
    return observer
}
