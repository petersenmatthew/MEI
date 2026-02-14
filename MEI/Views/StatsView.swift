import SwiftUI

struct StatsView: View {
    @Bindable var appState: AppState

    var totalToday: Int {
        appState.todayMessagesSent + appState.todayMessagesDeferred + appState.todayMessagesShadow
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Stats")
                    .font(.title2.bold())

                // Overview cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    StatCard(title: "Total", value: "\(totalToday)", icon: "message", color: .blue)
                    StatCard(title: "Sent", value: "\(appState.todayMessagesSent)", icon: "arrow.up.circle", color: .green)
                    StatCard(title: "Deferred", value: "\(appState.todayMessagesDeferred)", icon: "pause.circle", color: .yellow)
                    StatCard(title: "Shadow", value: "\(appState.todayMessagesShadow)", icon: "eye", color: .orange)
                }

                // Confidence
                GroupBox("Average Confidence") {
                    HStack {
                        Text(String(format: "%.2f", appState.todayAvgConfidence))
                            .font(.title)
                            .bold()
                        Spacer()
                        confidenceBar(appState.todayAvgConfidence)
                    }
                    .padding(.vertical, 4)
                }

                // Cost
                GroupBox("API Cost") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "$%.3f", Double(totalToday) * 0.0009))
                                .font(.title3.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("This Month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "$%.2f", appState.monthlyCost))
                                .font(.title3.bold())
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Recent feedback
                GroupBox("Feedback") {
                    let good = appState.recentExchanges.filter { $0.userFeedback == "good" }.count
                    let bad = appState.recentExchanges.filter { $0.userFeedback == "bad" }.count
                    let unrated = appState.recentExchanges.filter { $0.userFeedback == nil }.count

                    HStack(spacing: 20) {
                        Label("\(good) Good", systemImage: "hand.thumbsup.fill")
                            .foregroundStyle(.green)
                        Label("\(bad) Bad", systemImage: "hand.thumbsdown.fill")
                            .foregroundStyle(.red)
                        Label("\(unrated) Unrated", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }

    private func confidenceBar(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.tertiary)
                RoundedRectangle(cornerRadius: 4)
                    .fill(value > 0.8 ? .green : value > 0.6 ? .yellow : .red)
                    .frame(width: geo.size.width * CGFloat(value))
            }
        }
        .frame(width: 120, height: 8)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
