import SwiftUI
import UserNotifications

@main
struct MEIApp: App {
    @State private var appState = AppState()
    @State private var agentLoop: AgentLoop?
    @State private var showOnboarding = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(appState: appState)
                .onAppear {
                    startAgentIfNeeded()
                }
        } label: {
            Label {
                Text("MEI")
            } icon: {
                Image(systemName: menuBarIcon)
            }
        }
        .menuBarExtraStyle(.window)

        Window("MEI Dashboard", id: "dashboard") {
            DashboardView(appState: appState)
                .frame(minWidth: 700, minHeight: 500)
        }

        Settings {
            SettingsView(appState: appState)
        }
    }

    private var menuBarIcon: String {
        switch appState.mode {
        case .active: return "message.fill"
        case .shadow: return "eye.fill"
        case .paused: return "pause.circle"
        case .killed: return "xmark.circle"
        }
    }

    private func startAgentIfNeeded() {
        guard agentLoop == nil else { return }

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let loop = AgentLoop(appState: appState)
        agentLoop = loop
        Task {
            await loop.start()
        }

        // Check if first launch (no API key)
        if KeychainManager.load(key: "gemini_api_key") == nil {
            showOnboarding = true
        }
    }
}
