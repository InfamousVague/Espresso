import SwiftUI
import WidgetKit
import EspressoShared

/// `.systemMedium` Espresso layout. Two columns: left = brand →
/// cup + status + time → toggle button; right = mode label + jiggle
/// indicator + clamshell indicator. Mirrors Alfred Medium's split
/// proportions.
struct MediumView: View {
    let entry: EspressoEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // ── Left column.
            VStack(alignment: .leading, spacing: 4) {
                Text("ESPRESSO")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .widgetAccentable()

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: entry.stats.active
                          ? "cup.and.saucer.fill"
                          : "cup.and.saucer")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(entry.stats.active
                                         ? Color.accentColor
                                         : Color.secondary)

                    Text(entry.stats.active ? "Awake" : "Off")
                        .font(.system(.title2, design: .rounded)
                                .weight(.semibold))
                        .foregroundStyle(.primary)
                }

                if entry.stats.active, !subline.isEmpty {
                    Text(subline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .frame(maxWidth: .infinity, alignment: .leading)

            // ── Right column: mode + flags.
            VStack(alignment: .leading, spacing: 6) {
                Text("MODE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                    .widgetAccentable()

                Text(entry.stats.modeLabel.isEmpty
                     ? "—"
                     : entry.stats.modeLabel)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                flagRow(
                    icon: "cursorarrow.motionlines",
                    label: "Jiggle",
                    on: entry.stats.jiggleOn
                )
                flagRow(
                    icon: "laptopcomputer.and.arrow.down",
                    label: "Clamshell",
                    on: entry.stats.clamshellOn
                )

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    /// Two-tone status row — icon + label dimmed when off, accent
    /// when on. Keeps the right column reading at a glance.
    private func flagRow(icon: String, label: String,
                         on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10, weight: .medium))
            Spacer()
            Text(on ? "ON" : "off")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
        }
        .foregroundStyle(on ? .primary : .tertiary)
    }

    private var subline: String {
        if !entry.stats.remaining.isEmpty {
            return "\(entry.stats.remaining) left · \(entry.stats.elapsed) in"
        }
        if !entry.stats.elapsed.isEmpty {
            return "\(entry.stats.elapsed) in"
        }
        return ""
    }
}
