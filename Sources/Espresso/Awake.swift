import Foundation
import IOKit.pwr_mgt
import CoreGraphics
import ApplicationServices

enum AwakeMode: String, Codable, CaseIterable {
    case off
    case systemOnly
    case displayAndSystem

    var label: String {
        switch self {
        case .off: return "Off"
        case .systemOnly: return "System only"
        case .displayAndSystem: return "Display + System"
        }
    }
}

/// IOKit power-assertion manager — equivalent of the original Espresso's
/// `keepawake` crate (display / idle / system sleep prevention).
final class Awake {
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private(set) var mode: AwakeMode = .off

    func apply(_ mode: AwakeMode) {
        release()
        switch mode {
        case .off:
            break
        case .systemOnly:
            systemAssertion = create(kIOPMAssertionTypePreventUserIdleSystemSleep,
                                     "Espresso is keeping your system awake (display may sleep)")
        case .displayAndSystem:
            systemAssertion = create(kIOPMAssertionTypePreventUserIdleSystemSleep,
                                     "Espresso is keeping your computer awake")
            displayAssertion = create(kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                      "Espresso is keeping your display awake")
        }
        self.mode = mode
    }

    func release() {
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion); systemAssertion = 0 }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); displayAssertion = 0 }
        mode = .off
    }

    private func create(_ type: String, _ reason: String) -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        let r = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return r == kIOReturnSuccess ? id : 0
    }
}

/// Synthetic input — equivalent of the original Espresso's `enigo`-based
/// `simulation.rs`. Posting events needs Accessibility permission.
enum Jiggle {
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Small random mouse nudge then back (and optional Shift tap).
    static func perform(mouse: Bool, keyboard: Bool) {
        if mouse {
            let here = CGEvent(source: nil)?.location ?? .zero
            let dx = CGFloat(Int.random(in: -3...3))
            let dy = CGFloat(Int.random(in: -3...3))
            post(.mouseMoved, at: CGPoint(x: here.x + dx, y: here.y + dy))
            usleep(useconds_t(Int.random(in: 50_000...150_000)))
            post(.mouseMoved, at: here)
        }
        if keyboard {
            tapShift()
        }
    }

    private static func post(_ type: CGEventType, at p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private static func tapShift() {
        let shift: CGKeyCode = 0x38 // Left Shift
        CGEvent(keyboardEventSource: nil, virtualKey: shift, keyDown: true)?
            .post(tap: .cghidEventTap)
        usleep(useconds_t(Int.random(in: 30_000...80_000)))
        CGEvent(keyboardEventSource: nil, virtualKey: shift, keyDown: false)?
            .post(tap: .cghidEventTap)
    }
}
