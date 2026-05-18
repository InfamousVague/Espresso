import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (the modern replacement for the
/// original Espresso's tauri-plugin-autostart).
enum LoginItem {
    static var enabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Espresso login item error: \(error.localizedDescription)")
        }
    }
}
