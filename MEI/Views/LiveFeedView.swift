import SwiftUI
import Combine

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

            if appState.pendingReplies.isEmpty && appState.recentExchanges.isEmpty {
                ContentUnavailableView {
                    Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Messages will appear here as the agent processes them.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.pendingReplies) { pending in
                            PendingReplyCard(pending: pending)
                        }
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

struct PendingReplyCard: View {
    let pending: PendingReply
    @State private var remainingSeconds: Int = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(pending.contact)
                    .font(.headline)
                Spacer()
                Label(
                    remainingSeconds > 0 ? "Sending in \(remainingSeconds)s" : "Sending...",
                    systemImage: "timer"
                )
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.2))
                .clipShape(Capsule())
            }

            // Incoming message
            HStack(alignment: .top) {
                Text("\(pending.contact):")
                    .font(.subheadline.bold())
                Text(pending.incomingText)
                    .font(.subheadline)
            }

            // Planned response
            HStack(alignment: .top) {
                Text("Will send:")
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
                Text(pending.generatedText)
                    .font(.subheadline)
            }

            // Metadata
            HStack(spacing: 16) {
                Label(String(format: "%.2f", pending.confidence), systemImage: "gauge")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Countdown progress bar
                ProgressView(value: progress)
                    .tint(.blue)
                    .frame(maxWidth: 120)
            }
        }
        .padding()
        .background(.blue.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.blue.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { updateRemaining() }
        .onReceive(timer) { _ in updateRemaining() }
    }

    private var progress: Double {
        let remaining = pending.sendAt.timeIntervalSinceNow
        guard pending.totalDelay > 0 else { return 1.0 }
        return min(max(1.0 - remaining / pending.totalDelay, 0), 1.0)
    }

    private func updateRemaining() {
        remainingSeconds = max(0, Int(ceil(pending.sendAt.timeIntervalSinceNow)))
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
