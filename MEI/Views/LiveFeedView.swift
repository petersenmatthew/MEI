import SwiftUI

struct LiveFeedView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Live Feed")
                    .font(.title2.bold())
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: appState.mode.icon)
                        .foregroundStyle(appState.mode.color)
                    Text(appState.mode.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            if appState.recentExchanges.isEmpty {
                ContentUnavailableView {
                    Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Messages will appear here as the agent processes them.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.recentExchanges) { exchange in
                            ExchangeCard(exchange: exchange, appState: appState)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct ExchangeCard: View {
    let exchange: AgentExchange
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(exchange.contact)
                    .font(.headline)
                Text(exchange.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge
            }

            // Messages
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text("\(exchange.contact):")
                        .font(.subheadline.bold())
                    Text(exchange.incomingText)
                        .font(.subheadline)
                }

                if exchange.wasShadow {
                    HStack(alignment: .top) {
                        Text("Agent would say:")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                        Text(exchange.generatedText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let actual = exchange.actualReply {
                        HStack(alignment: .top) {
                            Text("You actually said:")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                            Text(actual)
                                .font(.subheadline)
                        }
                    }
                    if let matchScore = exchange.matchScore {
                        Text("Match score: \(Int(matchScore * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(alignment: .top) {
                        Text("You (agent):")
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                        Text(exchange.generatedText)
                            .font(.subheadline)
                    }
                }
            }

            // Metadata
            HStack(spacing: 16) {
                Label(String(format: "%.2f", exchange.confidence), systemImage: "gauge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(formatDelay(exchange.replyDelaySeconds), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(exchange.ragChunksUsed.count)", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Feedback buttons
                feedbackButtons
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusBadge: some View {
        Group {
            if exchange.wasShadow {
                Label("Shadow", systemImage: "eye")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2))
                    .clipShape(Capsule())
            } else if exchange.wasSent {
                Label("Sent", systemImage: "checkmark.circle")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2))
                    .clipShape(Capsule())
            } else {
                Label("Deferred", systemImage: "pause.circle")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.yellow.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }

    private var feedbackButtons: some View {
        HStack(spacing: 8) {
            Button {
                updateFeedback("good")
            } label: {
                Image(systemName: exchange.userFeedback == "good" ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .buttonStyle(.borderless)

            Button {
                updateFeedback("bad")
            } label: {
                Image(systemName: exchange.userFeedback == "bad" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .buttonStyle(.borderless)
        }
    }

    private func updateFeedback(_ feedback: String) {
        if let idx = appState.recentExchanges.firstIndex(where: { $0.id == exchange.id }) {
            appState.recentExchanges[idx].userFeedback = feedback
        }
    }

    private func formatDelay(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            let mins = Int(seconds / 60)
            let secs = Int(seconds) % 60
            return "\(mins)m \(secs)s"
        }
    }
}
