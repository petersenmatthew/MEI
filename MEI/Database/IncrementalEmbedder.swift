import Foundation
import CryptoKit

@MainActor
final class IncrementalEmbedder {
    private let messageReader: MessageReader
    private let geminiEmbedding = GeminiEmbedding()
    private let ragDatabase: RAGDatabase
    private let agentLog: AgentLogDatabase
    private var timer: Timer?

    /// Chunk size (number of messages per chunk)
    private let chunkSize = 10
    /// Overlap between consecutive chunks
    private let chunkOverlap = 3
    /// Minimum messages to form a chunk
    private let minChunkSize = 3
    /// Time gap (seconds) that splits conversations
    private let conversationGapSeconds: TimeInterval = 3600 // 60 minutes

    init(messageReader: MessageReader, ragDatabase: RAGDatabase, agentLog: AgentLogDatabase) {
        self.messageReader = messageReader
        self.ragDatabase = ragDatabase
        self.agentLog = agentLog
    }

    func startPeriodicUpdates(intervalHours: Double = 4) {
        // Run once on start, then periodically
        Task { @MainActor in
            await embedNewMessages()
        }
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
            // Get last embedded rowID from sync state
            let lastRowIDStr = agentLog.loadSyncState(key: "last_embedded_rowid") ?? "0"
            let lastRowID = Int64(lastRowIDStr) ?? 0

            print("[MEI] Incremental embedding: checking for messages since rowID \(lastRowID)...")

            // Fetch new messages grouped by contact
            let grouped = try await messageReader.fetchMessagesSince(rowID: lastRowID, limit: 500)

            guard !grouped.isEmpty else {
                print("[MEI] Incremental embedding: no new messages to embed")
                return
            }

            var totalChunks = 0
            var maxRowID = lastRowID

            for (contactID, messages) in grouped {
                // Track max rowID for sync state
                if let lastMsg = messages.last {
                    maxRowID = max(maxRowID, lastMsg.id)
                }

                // Skip contacts with too few messages
                guard messages.count >= minChunkSize else { continue }

                // Split into conversations by time gaps, then chunk
                let conversations = splitIntoConversations(messages)
                let chunks = conversations.flatMap { chunkConversation($0, contactID: contactID) }

                // Embed each chunk
                for chunk in chunks {
                    do {
                        let embedding = try await geminiEmbedding.embed(text: chunk.text)
                        let ragChunk = RAGChunk(
                            id: chunk.id,
                            contact: contactID,
                            timestamp: chunk.timestamp,
                            messageCount: chunk.messageCount,
                            isGroupChat: false,
                            chunkText: chunk.text,
                            topics: [],
                            embedding: embedding,
                            distance: nil
                        )
                        try ragDatabase.insertChunk(ragChunk)
                        totalChunks += 1

                        // Rate limit: ~50ms between API calls
                        try await Task.sleep(for: .milliseconds(50))
                    } catch {
                        print("[MEI] Failed to embed chunk for \(contactID): \(error)")
                    }
                }
            }

            // Update sync state
            agentLog.saveSyncState(key: "last_embedded_rowid", value: String(maxRowID))
            print("[MEI] Incremental embedding complete: \(totalChunks) new chunks embedded")

        } catch {
            print("[MEI] Incremental embedding error: \(error)")
        }
    }

    // MARK: - Chunking

    private struct RawChunk {
        let id: String
        let text: String
        let timestamp: Date
        let messageCount: Int
    }

    /// Split messages into conversations based on time gaps
    private func splitIntoConversations(_ messages: [ChatMessage]) -> [[ChatMessage]] {
        guard !messages.isEmpty else { return [] }
        var conversations: [[ChatMessage]] = []
        var current: [ChatMessage] = [messages[0]]

        for i in 1..<messages.count {
            let gap = messages[i].date.timeIntervalSince(messages[i - 1].date)
            if gap > conversationGapSeconds {
                conversations.append(current)
                current = []
            }
            current.append(messages[i])
        }
        if !current.isEmpty {
            conversations.append(current)
        }
        return conversations
    }

    /// Chunk a single conversation using sliding window with overlap
    private func chunkConversation(_ messages: [ChatMessage], contactID: String) -> [RawChunk] {
        guard messages.count >= minChunkSize else { return [] }

        // For short conversations, use as a single chunk
        if messages.count <= chunkSize {
            return [makeChunk(from: messages, contactID: contactID)]
        }

        // Sliding window
        var chunks: [RawChunk] = []
        var start = 0
        let step = chunkSize - chunkOverlap

        while start < messages.count {
            let end = min(start + chunkSize, messages.count)
            let window = Array(messages[start..<end])
            if window.count >= minChunkSize {
                chunks.append(makeChunk(from: window, contactID: contactID))
            }
            start += step
        }

        return chunks
    }

    private func makeChunk(from messages: [ChatMessage], contactID: String) -> RawChunk {
        let text = messages.map { msg in
            let sender = msg.isFromMe ? "Matthew" : "Them"
            return "\(sender): \(msg.text)"
        }.joined(separator: "\n")

        // MD5 hash of chunk text as ID (matches Python pipeline)
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        let id = digest.prefix(6).map { String(format: "%02x", $0) }.joined()

        return RawChunk(
            id: id,
            text: text,
            timestamp: messages.first?.date ?? Date(),
            messageCount: messages.count
        )
    }
}
