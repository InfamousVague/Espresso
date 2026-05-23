import SwiftUI
import WidgetKit
import EspressoShared

/// `.systemSmall` Espresso layout. Matches the family chrome (tracked
/// "ESPRESSO" caps brand at top, `.bordered` button at bottom). Hero
/// shows ON / OFF as a single-glyph cup + a status word; the
/// remaining or elapsed time slots underneath.
struct SmallView: View {
    let entry: EspressoEntry

    var body: some View {
        VStack(spacing: 4) {
            Text("ESPRESSO")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .widgetAccentable()

            Spacer(minLength: 0)

            // Hero — cup glyph + status word. Single line; the cup
            // doubles as the "current state" visual (saucer.fill when
            // active, plain saucer when off).
            Image(systemName: entry.stats.active
                  ? "cup.and.saucer.fill"
                  : "cup.and.saucer")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(entry.stats.active
                                 ? Color.accentColor
                                 : Color.secondary)

            Text(entry.stats.active ? "Awake" : "Off")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)

            // Sub-line: remaining time if a timer is running, else
            // elapsed if Espresso is on, else nothing.
            if entry.stats.active {
                Text(subline)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .widgetAccentable()
            }

            Spacer(minLength: 6)

            Button(intent: ToggleEspressoIntent()) {
                Label(entry.stats.active ? "Stop" : "Start",
                      systemImage: entry.stats.active
                        ? "stop.fill"
                        : "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .padding(14)
    }

    private var subline: String {
        if !entry.stats.remaining.isEmpty {
            return "\(entry.stats.remaining) left"
        }
        if !entry.stats.elapsed.isEmpty {
            return entry.stats.elapsed
        }
        return ""
    }
}
