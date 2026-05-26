import AppIntents

/// AppIntent driven by the widget's `Button(intent:)`.
///
/// Toggles keep-awake on/off. When off, activating uses the user's
/// last preferred mode + the "indefinite" preset (matches what
/// happens when they click the menu-bar icon in the panel UI with no
/// timer set).
///
/// Two-track dispatch (same pattern as Alfred):
///   • `openAppWhenRun = true` — system launches `Espresso.app` to
///     run `perform()` in that process. `IntentBus` closures
///     registered during `applicationDidFinishLaunching` fire there
///     and drive `EspressoStore`. Primary path for standalone users.
///   • `WidgetSignal.toggle.post()` — Darwin notification posted in
///     parallel. If the MattsSoftware launcher is hosting Espresso's
///     pane in its own process, that process subscribed in
///     `paneStart()` and responds directly without needing a second
///     Espresso.app launch. If both paths run on the same machine the
///     toggle is idempotent on the second call (the store no-ops if
///     the requested state matches the current state).
public struct ToggleEspressoIntent: AppIntent {
    public static var title: LocalizedStringResource =
        "Toggle Espresso"
    public static var description = IntentDescription(
        "Turn keep-awake on or off."
    )
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentBus.shared.toggle()
        WidgetSignal.toggle.post()
        return .result()
    }
}
