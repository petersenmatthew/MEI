import SwiftUI

struct MenuBarPopover: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            HStack {
                Image(systemName: appState.mode.icon)
                    .foregroundStyle(appState.mode.color)
                Text(appState.mode.rawValue)
                    .font(.headline)
                Spacer()
                modeMenu
            }

            Divider()

            // Today's stats
            VStack(alignment: .leading, spacing: 4) {
                let total = appState.todayMessagesSent + appState.todayMessagesDeferred + appState.todayMessagesShadow
                Text("Today: \(total) messages handled")
                    .font(.subheadline)

                HStack(spacing: 12) {
                    Label("\(appState.todayMessagesShadow)", systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("\(appState.todayMessagesSent)", systemImage: "arrow.up.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("\(appState.todayMessagesDeferred)", systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Open Dashboard") {
                    openWindow(id: "dashboard")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var modeMenu: some View {
        Menu {
            ForEach(AgentMode.allCases, id: \.self) { mode in
                Button {
                    appState.mode = mode
                } label: {
                    HStack {
                        Image(systemName: mode.icon)
                        Text(mode.rawValue)
                    }
                }
            }
        } label: {
            Text(appState.mode.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(appState.mode.color.opacity(0.2))
                .clipShape(Capsule())
        }
    }
}
