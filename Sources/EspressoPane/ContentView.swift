import SwiftUI
import AppKit

// Espresso palette — light "crema" accent for interactive elements,
// dark "espresso" brown to warm the panels.
private let accent = Color(red: 0.804, green: 0.620, blue: 0.420)     // #CD9E6B crema
private let accentDark = Color(red: 0.216, green: 0.137, blue: 0.090) // #382316 espresso

struct ContentView: View {
    @Environment(EspressoStore.self) private var store
    @State private var launchAtLogin = LoginItem.enabled

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 46)
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    stateCard
                    togglesCard
                }
                .padding(14)
            }
            Divider()
            footer
                .frame(height: 46)
        }
        .frame(width: 340, height: 540)
        .glassScrollers()
        .tint(accent)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: store.active ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 16))
                .foregroundStyle(store.active ? accent : .secondary)
            Text("ESPRESSO").font(.system(size: 13, weight: .semibold)).tracking(3)
            Spacer()
            Text(store.active
                 ? "\(store.mode.label)\(store.remaining.isEmpty ? "" : " · \(store.remaining)")"
                 : "Idle")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(store.active ? accent : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: State card

    @ViewBuilder
    private var stateCard: some View {
        if store.active {
            VStack(spacing: 10) {
                Text(store.preset == .indefinite ? "Awake — indefinite"
                                                  : "Awake — \(store.remaining)")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.mode.label)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button(role: .destructive) { store.deactivate() } label: {
                    Text("End Session").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(card)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: Binding(
                    get: { store.mode },
                    set: { store.setMode($0) }
                )) {
                    Text("Display + System").tag(AwakeMode.displayAndSystem)
                    Text("System only").tag(AwakeMode.systemOnly)
                }
                .pickerStyle(.segmented).labelsHidden()
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Text("Stay awake for").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                          spacing: 6) {
                    ForEach(TimerPreset.allCases) { p in
                        Button { store.activate(preset: p, mode: store.mode) } label: {
                            Text(p.label).frame(maxWidth: .infinity).padding(.vertical, 7)
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(card)
        }
    }

    // MARK: Toggles

    private var togglesCard: some View {
        VStack(spacing: 0) {
            toggleRow("Mouse jiggle",
                      sub: Jiggle.accessibilityTrusted ? "Keeps Slack/Teams/Zoom active"
                                                       : "Needs Accessibility permission",
                      isOn: Binding(get: { store.jiggleOn },
                                    set: { store.setJiggle($0) }))
            if store.jiggleOn {
                HStack {
                    Text("Profile").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(get: { store.simProfile },
                                                  set: { store.setSimProfile($0) })) {
                        ForEach(SimProfile.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider().padding(.horizontal, 12)
            toggleRow("Prevent sleep when lid closed",
                      sub: "Installs a scoped sudo rule (removable)",
                      isOn: Binding(get: { store.clamshellOn },
                                    set: { requestClamshell($0) }))
            Divider().padding(.horizontal, 12)
            toggleRow("Launch at login", sub: nil,
                      isOn: Binding(get: { launchAtLogin },
                                    set: { LoginItem.set($0); launchAtLogin = LoginItem.enabled }))
        }
        .padding(.vertical, 6)
        .background(card)
    }

    private func toggleRow(_ title: String, sub: String?, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                if let sub { Text(sub).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 6) {
            if let err = store.lastError {
                Text(err).font(.system(size: 10)).foregroundStyle(.red)
                    .lineLimit(2).onTapGesture { store.lastError = nil }
            }
            HStack(spacing: 10) {
                if store.clamshellSudoersInstalled {
                    Button {
                        store.removeClamshellRule()
                    } label: {
                        Image(systemName: "xmark.shield")
                    }
                    .controlSize(.small)
                    .help("Remove lid-closed rule")
                }
                Spacer()
                Text(store.active ? "Awake \(store.awakeElapsed)" : "Idle")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text("Panic ⌃⇧⎋")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .controlSize(.small)
                .help("Quit Espresso")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(accentDark.opacity(0.34))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(accent.opacity(0.20), lineWidth: 1))
    }

    private func requestClamshell(_ on: Bool) {
        guard on else { store.setClamshell(false); return }
        let alert = NSAlert()
        alert.messageText = "Prevent sleep when the lid is closed?"
        alert.informativeText = Clamshell.disclosure
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install & Enable")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.setClamshell(true)
        }
    }
}
