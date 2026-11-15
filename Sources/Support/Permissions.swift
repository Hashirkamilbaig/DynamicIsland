import AppKit
import ApplicationServices

enum Permissions {
    /// Accessibility is optional in v1 (reserved for global hotkeys later).
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        Log.app.info("Accessibility trust prompt requested")
    }
}
