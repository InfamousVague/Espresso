# Espresso (Linux)

Linux-native sibling of the macOS Swift build at the repo root. The
Mac and Linux builds ship under the same product name and version
but are **separate native binaries** — they share no code, only a
contract: "click → keep the machine awake; click → release."

## Status

**Scaffold only.** The macOS build is the current shipping artifact;
this directory exists so the Linux work has a place to land
incrementally without disrupting the Mac release pipeline.

## Stack

| Layer            | Choice                                           |
| ---------------- | ------------------------------------------------ |
| Language         | Rust (2021)                                      |
| Idle inhibit     | `org.freedesktop.login1.Manager.Inhibit` (D-Bus) |
| D-Bus client     | [`zbus`](https://docs.rs/zbus)                   |
| Tray             | [`ksni`](https://docs.rs/ksni) (StatusNotifierItem) |
| Mouse jiggle     | `uinput` (kernel virtual input) or X11 `XTest`   |
| Hotkey (panic)   | `evdev` + grab on key chord                      |
| Packaging        | `.deb` (`cargo-deb`) · `.rpm` (`cargo-generate-rpm`) · Flatpak |

`systemd-logind`'s **Inhibit** is the right way to keep a Linux box
awake — it returns a file descriptor, and holding it open suppresses
idle/suspend. No polkit prompt, no root required.

## Feature parity vs the Mac build

| Mac feature                              | Linux equivalent                            |
| ---------------------------------------- | ------------------------------------------- |
| `IOPMAssertionCreateWithName` (display + system) | `Inhibit("idle:sleep", ...)` via logind |
| Lid-closed override (clamshell)          | `HandleLidSwitch=ignore` (systemd-logind)   |
| Mouse-jiggle Slack/Teams/Zoom            | `uinput` synthetic mouse motion             |
| Panic hotkey (⌃⇧⎋)                       | `evdev` grab — chord configurable           |
| Tray icon, idle⇄active glyph             | `ksni` (works on KDE, GNOME w/ extension, Cinnamon) |

## Honest ceilings

- **Wayland tray**: GNOME no longer ships a system-tray protocol. Users on vanilla GNOME need the AppIndicator extension; KDE / Cinnamon / XFCE / Sway work out of the box.
- **Mouse-jiggle on Wayland**: `XTest` doesn't apply. `uinput` works but needs the user in the `input` group (or a udev rule we ship in the `.deb`).
- **Lid override**: edits `/etc/systemd/logind.conf` — needs root once at install. Reversible.

## Roadmap

1. CLI MVP: `espresso 1h` ⇒ holds an Inhibit for 1 hour.
2. Tray app: `ksni` integration with the same preset grid as Mac.
3. Mouse-jiggle + profile presets (Slack / Teams / Zoom).
4. Packaging: `.deb` + `.rpm` in CI alongside the macOS `.dmg`.
