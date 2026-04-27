// Seedo/Services/FocusModeService.swift
import Foundation
import Combine
import AppKit

final class FocusModeService {
    static let shared = FocusModeService()
    
    private let appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()
    private var lastState: Bool = false
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe Deep Focus state, tracking state, and BreakScheduler work state
        Publishers.CombineLatest(
            Publishers.CombineLatest4(
                appState.$isDeepFocusActive,
                appState.$isTracking,
                BreakScheduler.shared.$isFocusActive,
                BreakScheduler.shared.$isBreakInProgress
            ),
            appState.$isMacFocusModeEnabled
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] tuple, isEnabled in
            let (isDeepFocus, isTracking, isFocusActive, isBreak) = tuple
            let shouldBeOn = isDeepFocus || (isTracking && isFocusActive && !isBreak)
            self?.handleFocusStateChange(isActive: shouldBeOn, isEnabled: isEnabled)
        }
        .store(in: &cancellables)
    }
    
    private func handleFocusStateChange(isActive: Bool, isEnabled: Bool) {
        // If the setting is disabled, we should ensure DND is OFF
        // if we were the ones who turned it ON previously.
        if !isEnabled {
            if lastState {
                print("[FocusModeService] Setting disabled while focus was ON. Forcing OFF.")
                setFocusMode(enabled: false)
                lastState = false
            }
            return
        }
        
        guard isActive != lastState else { return }
        
        lastState = isActive
        print("[FocusModeService] State change -> \(isActive ? "ON" : "OFF")")
        setFocusMode(enabled: isActive)
    }
    
    private func setFocusMode(enabled: Bool) {
        let stateStr = enabled ? "on" : "off"
        
        // This script tries several ways to toggle DND/Focus
        // 1. Try "shortcuts" command (Best performance if user has the shortcut)
        // 2. Fallback to UI scripting (Requires Accessibility permission)
        let script = """
        try
            -- Try pre-defined shortcuts (English and Chinese names)
            try
                do shell script "shortcuts run 'Do Not Disturb' --input '\(stateStr)'"
            on error
                do shell script "shortcuts run '勿扰模式' --input '\(stateStr)'"
            end try
        on error
            try
                -- UI Scripting fallback: Find the Focus item in the menu bar
                tell application "System Events"
                    tell process "Control Center"
                        -- Find the focus/DND item by common accessibility descriptions
                        set focusItem to (first menu bar item whose accessibility description contains "Focus" or accessibility description contains "专注" or accessibility description contains "勿扰") of menu bar 1
                        
                        -- Note: On many macOS versions, AXPress on the menu item toggles DND 
                        -- if it's the specific mode icon. If it's the general Focus icon, it opens a menu.
                        perform action "AXPress" of focusItem
                    end tell
                end tell
            on error err
                log "FocusModeService UI Scripting failed: " & err
            end try
        end try
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)
            
            if let err = error {
                print("[FocusModeService] AppleScript execution error: \(err)")
            }
        }
    }
}
