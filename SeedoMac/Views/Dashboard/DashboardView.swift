// SeedoMac/Views/Dashboard/DashboardView.swift
import SwiftUI

enum DashboardTab: String, CaseIterable {
    case stats      = "Stats"
    case categories = "Categories"
    case offline    = "Offline"
    case settings   = "Settings"

    var icon: String {
        switch self {
        case .stats:      return "chart.bar.fill"
        case .categories: return "tag.fill"
        case .offline:    return "pencil.and.list.clipboard"
        case .settings:   return "gearshape.fill"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: DashboardTab = .stats

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selectedTab {
            case .stats:      StatsView(appState: appState)
            case .categories: CategoryView()
            case .offline:    OfflineView()
            case .settings:   SettingsView(appState: appState)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
