// SeedoMac/App/SeedoApp.swift
import SwiftUI

@main
struct SeedoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // No visible scenes — UI lives in NSStatusItem + NSPopover + NSWindow
        Settings { EmptyView() }
    }
}
