// Seedo/Views/Dashboard/DashboardWindow.swift
import AppKit
import SwiftUI

class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Seedo"
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: DashboardView(appState: appState)
                .preferredColorScheme(appState.appearance == "light" ? .light : (appState.appearance == "dark" ? .dark : nil))
        )
    }

    required init?(coder: NSCoder) { fatalError("Use init(appState:)") }

    func windowWillClose(_ notification: Notification) {
        // Window hides; app continues in Menu Bar
    }
}

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Seedo Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 500)
        super.init(window: window)
        window.delegate = self
        
        let hostingController = NSHostingController(
            rootView: SettingsView(appState: appState)
                .frame(width: 450, height: 600)
                .preferredColorScheme(appState.appearance == "light" ? .light : (appState.appearance == "dark" ? .dark : nil))
        )
        window.contentViewController = hostingController
    }

    required init?(coder: NSCoder) { fatalError("Use init(appState:)") }

    func windowWillClose(_ notification: Notification) {
        // Just hide
    }
}
