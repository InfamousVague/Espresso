//! Linux build of Espresso. Scaffold only — see ../README.md for
//! the implementation plan + OS-specific ceilings.
//!
//! Real version will hold an idle-inhibit fd from
//! `org.freedesktop.login1.Manager.Inhibit` and front it with a
//! `ksni` tray icon matching the macOS preset grid.

fn main() {
    eprintln!(
        "espresso (linux): scaffold only — see linux/README.md for \
         the implementation plan."
    );
    std::process::exit(0);
}
