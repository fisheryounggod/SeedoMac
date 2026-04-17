// SeedoMac/BreakReminder/BreakOverlayWindowController.swift
import AppKit
import SwiftUI

final class BreakOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class BreakOverlayWindowController: NSWindowController {
    
    private let startTs: Int64
    private let endTs: Int64
    private let durationSecs: Double
    private let canPostpone: Bool
    private let isLongBreak: Bool
    private let durationMins: Int
    private let sessionIndex: Int
    private let totalSessions: Int
    
    init(startTs: Int64, endTs: Int64, durationSecs: Double, canPostpone: Bool,
         isLongBreak: Bool, durationMins: Int, sessionIndex: Int, totalSessions: Int) {
        self.startTs = startTs
        self.endTs = endTs
        self.durationSecs = durationSecs
        self.canPostpone = canPostpone
        self.isLongBreak = isLongBreak
        self.durationMins = durationMins
        self.sessionIndex = sessionIndex
        self.totalSessions = totalSessions
        
        // Setup Window
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let window = BreakOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .screenSaver // Above everything
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false // We WANT mouse events
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        super.init(window: window)
        
        let contentView = BreakOverlayView(
            startTs: startTs,
            endTs: endTs,
            durationSecs: durationSecs,
            canPostpone: canPostpone,
            isLongBreak: isLongBreak,
            durationMins: durationMins,
            sessionIndex: sessionIndex,
            totalSessions: totalSessions,
            onStartBreak: { 
                BreakScheduler.shared.startBreak()
            },
            onPostpone: { [weak self] in
                BreakScheduler.shared.postponeBreak()
                self?.close()
            },
            onSkip: { [weak self] summary in
                BreakScheduler.shared.skipBreak(summary: summary, startTs: startTs, endTs: endTs)
                self?.close()
            },
            onFinishBreak: { [weak self] summary in
                BreakScheduler.shared.endBreak(summary: summary, outcome: "completed", startTs: startTs, endTs: endTs)
                self?.close()
            },
            onDisableToday: { [weak self] in
                BreakScheduler.shared.disableToday()
                self?.close()
            }
        )
        
        window.contentView = NSHostingView(rootView: contentView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // Support ESC to postpone
    override func cancelOperation(_ sender: Any?) {
        if canPostpone {
            BreakScheduler.shared.postponeBreak()
            self.close()
        }
    }
}
