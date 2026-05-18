import Foundation

/// Lid-closed ("clamshell") sleep override — ported from the original Espresso
/// `clamshell.rs`. Installs a narrowly-scoped passwordless-sudo rule so
/// `pmset -a disablesleep` can run without a prompt each time. Opt-in only;
/// the UI discloses exactly what this writes and offers removal.
///
/// All operations return `nil` on success or an error message string.
enum Clamshell {
    static let sudoersPath = "/etc/sudoers.d/espresso_power"
    private static let sudoersContent = """
    Cmnd_Alias PMSET_ESPRESSO = /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
    %admin ALL=(ALL) NOPASSWD: PMSET_ESPRESSO
    """

    static var sudoersInstalled: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    /// Human-readable disclosure shown before the admin prompt.
    static let disclosure = """
    To keep your Mac awake with the lid closed, Espresso installs a small \
    system rule at \(sudoersPath) that lets it run only:

        pmset -a disablesleep 1   (and …0 to undo)

    without asking for your password each time. It grants nothing else. \
    You can remove it anytime from Espresso's settings.
    """

    @discardableResult
    static func installSudoers() -> String? {
        if sudoersInstalled { return nil }
        let escaped = sudoersContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let script = "do shell script \"printf '\(escaped)\\n' | tee \(sudoersPath) > /dev/null && chmod 440 \(sudoersPath)\" with administrator privileges"
        return runOsascript(script)
    }

    static func removeSudoers() -> String? {
        guard sudoersInstalled else { return nil }
        return runOsascript("do shell script \"rm -f \(sudoersPath)\" with administrator privileges")
    }

    static func enable() -> String? {
        if !sudoersInstalled, let err = installSudoers() { return err }
        return pmset(disable: "1")
    }

    static func disable() -> String? {
        pmset(disable: "0")
    }

    static var isActive: Bool {
        let out = shell("/usr/bin/pmset", ["-g"]) ?? ""
        return out.split(separator: "\n").contains {
            $0.contains("SleepDisabled") && $0.trimmingCharacters(in: .whitespaces).hasSuffix("1")
        }
    }

    private static func pmset(disable value: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["/usr/bin/pmset", "-a", "disablesleep", value]
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        do { try p.run() } catch { return "Failed to run pmset: \(error.localizedDescription)" }
        p.waitUntilExit()
        if p.terminationStatus == 0 { return nil }
        let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return "pmset failed: \(msg)"
    }

    private static func runOsascript(_ script: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        do { try p.run() } catch { return "osascript failed: \(error.localizedDescription)" }
        p.waitUntilExit()
        if p.terminationStatus == 0 { return nil }
        let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if msg.contains("User canceled") || msg.contains("-128") {
            return "Authorization cancelled."
        }
        return msg.isEmpty ? "Authorization failed." : msg
    }

    private static func shell(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }
}
