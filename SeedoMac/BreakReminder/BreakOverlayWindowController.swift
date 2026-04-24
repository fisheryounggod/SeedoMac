// Seedo/BreakReminder/BreakOverlayWindowController.swift
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
    
    private let initialSummary: String
    private let initialNotes: String
    private let initialCategoryId: String?
    
    private var overlayWindows: [NSWindow] = []
    
    init(startTs: Int64, endTs: Int64, durationSecs: Double, canPostpone: Bool,
         isLongBreak: Bool, durationMins: Int, sessionIndex: Int, totalSessions: Int,
         initialSummary: String = "", initialNotes: String = "", initialCategoryId: String? = nil) {
        self.startTs = startTs
        self.endTs = endTs
        self.durationSecs = durationSecs
        self.canPostpone = canPostpone
        self.isLongBreak = isLongBreak
        self.durationMins = durationMins
        self.sessionIndex = sessionIndex
        self.totalSessions = totalSessions
        self.initialSummary = initialSummary
        self.initialNotes = initialNotes
        self.initialCategoryId = initialCategoryId
        
        super.init(window: nil)
        
        setupWindows()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindows() {
        for screen in NSScreen.screens {
            let window = BreakOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let contentView = BreakOverlayView(
                startTs: startTs,
                endTs: endTs,
                durationSecs: durationSecs,
                canPostpone: canPostpone,
                isLongBreak: isLongBreak,
                durationMins: durationMins,
                sessionIndex: sessionIndex,
                totalSessions: totalSessions,
                initialSummary: initialSummary,
                initialNotes: initialNotes,
                initialCategoryId: initialCategoryId,
                onStartBreak: { 
                    BreakScheduler.shared.startBreak()
                },
                onPostpone: { [weak self] in
                    BreakScheduler.shared.postponeBreak()
                    self?.close()
                },
                onSkip: { [weak self] summary, notes, catId in
                    BreakScheduler.shared.skipBreak(summary: summary, title: notes, categoryId: catId, startTs: self?.startTs ?? 0, endTs: self?.endTs ?? 0)
                    self?.close()
                },
                onFinishBreak: { [weak self] summary, notes, catId in
                    BreakScheduler.shared.endBreak(summary: summary, title: notes, categoryId: catId, outcome: "completed", startTs: self?.startTs ?? 0, endTs: self?.endTs ?? 0)
                    self?.close()
                },
                onDisableToday: { [weak self] in
                    BreakScheduler.shared.disableToday()
                    self?.close()
                }
            )
            
            window.contentView = NSHostingView(rootView: contentView)
            overlayWindows.append(window)
        }
        
        // Use the first window as the primary window for NSWindowController
        if let first = overlayWindows.first {
            self.window = first
        }
    }
    
    override func showWindow(_ sender: Any?) {
        for window in overlayWindows {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    override func close() {
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
        super.close()
    }
    
    // Support ESC to postpone
    override func cancelOperation(_ sender: Any?) {
        if canPostpone {
            BreakScheduler.shared.postponeBreak()
            self.close()
        }
    }
}
