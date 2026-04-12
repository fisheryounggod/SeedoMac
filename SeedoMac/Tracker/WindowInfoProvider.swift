// SeedoMac/Tracker/WindowInfoProvider.swift
import AppKit

enum WindowInfoProvider {
    /// Returns the frontmost window title for `pid`, or nil if AX permission is denied or unavailable.
    static func getTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let axApp = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard result == .success, let window = focusedWindow else { return nil }

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            // swiftlint:disable:next force_cast
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleRef
        )
        guard titleResult == .success, let title = titleRef as? String else { return nil }
        return title.isEmpty ? nil : title
    }

    /// Returns true if the app has Accessibility permission.
    static var isPermissionGranted: Bool { AXIsProcessTrusted() }

    /// Prompts the system Accessibility permission dialog.
    /// Only shows the dialog if not already trusted. Safe to call multiple times.
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}
