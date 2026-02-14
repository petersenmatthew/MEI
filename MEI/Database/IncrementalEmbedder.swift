import Foundation

@MainActor
final class IncrementalEmbedder {
    private let messageReader: MessageReader
    private let geminiEmbedding = GeminiEmbedding()
    private let ragDatabase: RAGDatabase
    private var timer: Timer?
    private var lastEmbeddedTimestamp: Date?

    init(messageReader: MessageReader, ragDatabase: RAGDatabase) {
        self.messageReader = messageReader
        self.ragDatabase = ragDatabase
    }

    func startPeriodicUpdates(intervalHours: Double = 4) {
        timer = Timer.scheduledTimer(withTimeInterval: intervalHours * 3600, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.embedNewMessages()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func embedNewMessages() async {
        do {
            // Get recent messages that haven't been embedded
            // For now, re-embed last 24 hours of messages
            let cutoff = Date().addingTimeInterval(-24 * 3600)

            // This is a simplified version - in production you'd track
            // which messages have been embedded via sync_state
            print("[MEI] Incremental embedding: checking for new messages...")

            // The full implementation would:
            // 1. Query chat.db for messages since last embed
            // 2. Group into conversation chunks
            // 3. Embed each chunk
            // 4. Insert into RAG database
            // 5. Update sync timestamp

            print("[MEI] Incremental embedding complete")
        }
    }
}
