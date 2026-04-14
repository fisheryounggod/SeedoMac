// SeedoMac/Tracker/BrowserURLProvider.swift
import AppKit
import ApplicationServices

enum BrowserURLProvider {

    // MARK: - Known browser bundle IDs

    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Canary",
        "company.thebrowser.Browser",      // Arc
        "com.brave.Browser",
        "com.brave.Browser.nightly",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaNext",
        "com.kagi.kagimacOS",              // Orion
    ]

    static func isBrowser(bundleId: String) -> Bool {
        browserBundleIDs.contains(bundleId)
    }

    // MARK: - URL extraction

    /// Returns the current URL from a browser window using the Accessibility API.
    /// Returns nil if AX permission is not granted, the app is not a browser, or extraction fails.
    static func getURL(pid: pid_t, bundleId: String) -> String? {
        guard AXIsProcessTrusted(), isBrowser(bundleId: bundleId) else { return nil }

        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused window
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowValue = windowRef,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        let window = windowValue as! AXUIElement // safe: type ID verified above

        // Strategy 1: kAXURLAttribute directly on the window (works for some browsers)
        var urlRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXURLAttribute as CFString, &urlRef) == .success,
           let urlValue = urlRef {
            // kAXURLAttribute may return a URL or a String depending on the app
            if let urlObj = urlValue as? URL, isHTTP(urlObj.absoluteString) {
                return urlObj.absoluteString
            }
            if let urlStr = urlValue as? String, isHTTP(urlStr) {
                return urlStr
            }
        }

        // Strategy 2: Walk the AX tree to find a text field whose value is an HTTP URL
        return searchURL(in: window, depth: 0)
    }

    // MARK: - AX tree walk

    private static func searchURL(in element: AXUIElement, depth: Int) -> String? {
        guard depth < 7 else { return nil }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Check text fields and combo boxes for a URL value
        if role == kAXTextFieldRole || role == "AXComboBox" {
            var valueRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
            if let str = valueRef as? String, isHTTP(str) {
                return str
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let childrenValue = childrenRef,
              CFGetTypeID(childrenValue) == CFArrayGetTypeID() else { return nil }
        let children = childrenValue as! CFArray as [AnyObject] as? [AXUIElement] ?? []

        for child in children {
            if let url = searchURL(in: child, depth: depth + 1) {
                return url
            }
        }
        return nil
    }

    // MARK: - Domain helper

    /// Returns the domain (host) from a URL string, e.g. "https://github.com/foo" → "github.com"
    static func domain(from urlString: String) -> String? {
        URL(string: urlString)?.host
    }

    private static func isHTTP(_ str: String) -> Bool {
        str.hasPrefix("http://") || str.hasPrefix("https://")
    }
}
