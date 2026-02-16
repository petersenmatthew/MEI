import SwiftUI

struct TestInjectionView: View {
    @Bindable var appState: AppState
    let agentLoop: AgentLoop?

    @State private var contactID = "+15555550100"
    @State private var contactName = "Test Contact"
    @State private var messageText = ""
    @State private var isProcessing = false
    @State private var lastResult: TestResult?

    enum TestResult {
        case success
        case agentNotReady
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "hammer.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Test Injection")
                    .font(.title2.bold())
            }

            Text("Inject fake messages to test the full pipeline without sending real iMessages.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Agent mode warning
            if !appState.shouldProcess {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Agent must be in Active or Shadow mode to process test messages.")
                        .font(.callout)
                }
                .padding()
                .background(.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Form
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    // Contact ID
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contact ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Phone number", text: $contactID)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Contact Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contact Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Display name", text: $contactName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Message Text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message Text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $messageText)
                            .font(.body)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(.separatorColor), lineWidth: 1)
                            )
                    }
                }
                .padding(.vertical, 8)
            }

            // Inject Button
            HStack {
                Button {
                    Task {
                        await injectMessage()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text("Processing...")
                        } else {
                            Image(systemName: "play.fill")
                            Text("Inject Message")
                        }
                    }
                    .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isProcessing || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentLoop == nil)

                Spacer()

                // Status indicator
                if let result = lastResult {
                    statusView(for: result)
                }
            }

            Spacer()

            // Info box
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What happens when you inject:", systemImage: "info.circle")
                        .font(.callout.bold())

                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("Safety checks run (skip contact mode & active hours)")
                        bulletPoint("RAG retrieval searches for similar past conversations")
                        bulletPoint("Style profile loads (if available for contact)")
                        bulletPoint("Gemini generates a response")
                        bulletPoint("Behavior engine calculates reply delay")
                        bulletPoint("Response logged to Live Feed (no actual iMessage sent)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
    }

    @ViewBuilder
    private func statusView(for result: TestResult) -> some View {
        switch result {
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Done")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        case .agentNotReady:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.yellow)
                Text("Agent not ready")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        case .error(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.callout)
        }
    }

    private func injectMessage() async {
        guard let agentLoop = agentLoop else {
            lastResult = .agentNotReady
            return
        }

        guard appState.shouldProcess else {
            lastResult = .error("Agent paused/killed")
            return
        }

        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        isProcessing = true
        lastResult = nil

        await agentLoop.injectTestMessage(
            text: trimmedText,
            contactID: contactID,
            contactName: contactName
        )

        isProcessing = false
        lastResult = .success
        messageText = ""
    }
}
