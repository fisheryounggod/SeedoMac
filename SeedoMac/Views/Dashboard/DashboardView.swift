import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        StatsView(appState: appState)
            .frame(minWidth: 640, minHeight: 480)
    }
}
