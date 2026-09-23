// Seedo/Views/Dashboard/DashboardWindow.swift
import AppKit
import SwiftUI

class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Seedo"
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Seedo Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 400, height: 500)
        super.init(window: window)
        window.delegate = self
        
        let hostingController = NSHostingController(
            rootView: SettingsView(appState: appState)
                .frame(minWidth: 400, minHeight: 400)
                .preferredColorScheme(appState.appearance == "light" ? .light : (appState.appearance == "dark" ? .dark : nil))
        )
        window.contentViewController = hostingController
    }

    required init?(coder: NSCoder) { fatalError("Use init(appState:)") }

    func windowWillClose(_ notification: Notification) {
        // Just hide
    }
}

final class ManualRecordWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private var isSaving = false

    init(appState: AppState, duration: Double?, onSave: @escaping (WorkSession, @escaping (Result<Void, Error>) -> Void) -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = KeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "手动记录活动"
        window.minSize = NSSize(width: 500, height: 400)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView:
            AddActivitySheet(initialDuration: duration, onSave: { [weak self] session, completion in
                self?.isSaving = true
                onSave(session) { result in
                    self?.isSaving = false
                    completion(result)
                    if case .success = result { self?.close() }
                }
            }, onCancel: { [weak self] in self?.close() })
            .preferredColorScheme(appState.appearance == "light" ? .light : (appState.appearance == "dark" ? .dark : nil))
        )
        window.isOpaque = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(appState:duration:onSave:)") }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !isSaving
    }
}
