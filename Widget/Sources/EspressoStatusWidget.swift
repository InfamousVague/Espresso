import WidgetKit
import SwiftUI
import EspressoShared

/// Espresso's one widget: keep-awake status + one-tap toggle. Small
/// gets the on/off headline + remaining/elapsed time + a toggle pill;
/// medium adds the mode label + jiggle/clamshell indicators.
struct EspressoStatusWidget: Widget {
    let kind: String = "EspressoStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EspressoProvider()) {
            entry in
            EspressoWidgetView(entry: entry)
                // Forces `.accented` in the SwiftUI subtree so adaptive
                // code (button styles, image rendering) reads the
                // dimmed-glass mode regardless of focus. Visual
                // consistency with Alfred / Port / Quarantine.
                .environment(\.widgetRenderingMode, .accented)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Espresso")
        .description("Keep your Mac awake at a glance, with a one-tap toggle.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct EspressoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EspressoEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            default:            SmallView(entry: entry)
            }
        }
        // Desktop-widget tap → MattsSoftware launcher routes to
        // the Espresso pane via the `mattssoftware://` scheme it
        // registers. Without this URL hook, tapping launches the
        // standalone Espresso bundle id, SuiteGuard exits in
        // merged mode, and nothing visible happens.
        .widgetURL(URL(string: "mattssoftware://espresso"))
    }
}
