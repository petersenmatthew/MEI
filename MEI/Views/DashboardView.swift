import SwiftUI

struct DashboardView: View {
    @Bindable var appState: AppState
    let agentLoop: AgentLoop?

    var body: some View {
        TabView {
            LiveFeedView(appState: appState)
                .tabItem {
                    Label("Live Feed", systemImage: "bubble.left.and.bubble.right")
                }

            ContactsView(appState: appState)
                .tabItem {
                    Label("Contacts", systemImage: "person.2")
                }

            StatsView(appState: appState)
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }

            SettingsView(appState: appState)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }

            TestInjectionView(appState: appState, agentLoop: agentLoop)
                .tabItem {
                    Label("Test", systemImage: "hammer.fill")
                }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
