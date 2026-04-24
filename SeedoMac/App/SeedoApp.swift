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
            CommandGroup(replacing: .appSettings) { }
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
