// Seedo/App/SeedoApp.swift
import SwiftUI

@main
struct SeedoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @ObservedObject var appState = AppState.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { delegate.showSettingsWindow() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("手动添加记录…") { delegate.addManualRecord() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("专注") {
                Button(appState.isTracking ? "暂停追踪" : "开始追踪") { delegate.toggleTracking() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("切换纯专注模式") { delegate.togglePureFocus() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("详细统计") { delegate.openStats() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch appState.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
