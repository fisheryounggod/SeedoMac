// Seedo/Services/AutoExportService.swift
import Foundation
import AppKit
import Combine

final class AutoExportService {
    static let shared = AutoExportService()
    
    private var timer: Timer?
    private let appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupObservers()
        startTimer()
    }
    
    private func setupObservers() {
        // Restart timer when interval or status changes
        NotificationCenter.default.publisher(for: .settingsDidSave)
            .sink { [weak self] _ in
                self?.startTimer()
            }
            .store(in: &cancellables)
    }
    
    func startTimer() {
        timer?.invalidate()
        
        guard appState.isAutoExportEnabled && !appState.autoExportPath.isEmpty else {
            print("[AutoExportService] Auto export disabled or no path set.")
            return
        }
        
        let interval = TimeInterval(appState.autoExportIntervalHours * 3600)
        print("[AutoExportService] Starting timer with interval: \(appState.autoExportIntervalHours) hours")
        
        // Check if we should export now (e.g. if it's been longer than the interval since last export)
        checkAndPerformExport()
        
        // Schedule next exports
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkAndPerformExport()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    private func checkAndPerformExport() {
        guard appState.isAutoExportEnabled && !appState.autoExportPath.isEmpty else { return }
        
        let lastExport = UserDefaults.standard.double(forKey: "last_auto_export_ts")
        let now = Date().timeIntervalSince1970
        let intervalSecs = Double(appState.autoExportIntervalHours * 3600)
        
        if now - lastExport >= intervalSecs {
            performExport()
        }
    }
    
    private func performExport() {
        guard let bookmarkData = appState.autoExportBookmark else {
            print("[AutoExportService] No bookmark data for auto export path.")
            return
        }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("[AutoExportService] Bookmark is stale.")
                // Should probably inform user via UI
            }
            
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                
                print("[AutoExportService] Performing auto export to: \(url.path)")
                DataManagementService.shared.performSilentExport(to: url) { result in
                    switch result {
                    case .success(let savedURL):
                        print("[AutoExportService] Export successful: \(savedURL.lastPathComponent)")
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_auto_export_ts")
                    case .failure(let error):
                        print("[AutoExportService] Export failed: \(error.localizedDescription)")
                    }
                }
            } else {
                print("[AutoExportService] Failed to access security scoped resource.")
            }
        } catch {
            print("[AutoExportService] Error resolving bookmark: \(error)")
        }
    }
}
