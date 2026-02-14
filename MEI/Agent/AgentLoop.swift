import Foundation
import UserNotifications

@MainActor
final class AgentLoop {
    private let appState: AppState
    private let messageReader = MessageReader()
    private let messageSender = MessageSender()
    private let geminiClient = GeminiClient()
    private let geminiEmbedding = GeminiEmbedding()
    private let ragDatabase = RAGDatabase()
    private let agentLog = AgentLogDatabase()

    private var pollTimer: Timer?
    private var isProcessing = false

    init(appState: AppState) {
        self.appState = appState
    }

    func start() async {
        do {
            try await messageReader.open()

            // Start from the latest message so we don't process old ones
            let maxRowID = try await messageReader.getMaxRowID()
            await messageReader.setLastProcessedRowID(maxRowID)

            // Load saved state
            if let savedRowID = agentLog.loadSyncState(key: "last_processed_rowid"),
               let rowID = Int64(savedRowID) {
                await messageReader.setLastProcessedRowID(rowID)
            }

            try ragDatabase.open()
            try agentLog.open()

            startPolling()
            print("[MEI] Agent loop started. Polling every 2 seconds.")
        } catch {
            print("[MEI] Failed to start agent loop: \(error)")
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        print("[MEI] Agent loop stopped.")
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.poll()
            }
        }
    }

    private func poll() async {
        guard !isProcessing else { return }
        guard appState.shouldProcess else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let newMessages = try await messageReader.fetchNewMessages()

            for message in newMessages {
                await processMessage(message)

                // Save progress
                let rowID = await messageReader.getLastProcessedRowID()
                agentLog.saveSyncState(key: "last_processed_rowid", value: String(rowID))
            }
        } catch {
            print("[MEI] Poll error: \(error)")
        }
    }

    private func processMessage(_ message: ChatMessage) async {
        // 1. Safety checks
        let safety = await SafetyChecks.shouldProcess(
            message: message,
            appState: appState,
            messageReader: messageReader
        )

        switch safety {
        case .skip(let reason):
            print("[MEI] Skipping \(message.displayName): \(reason)")
            return
        case .defer(let reason):
            print("[MEI] Deferring \(message.displayName): \(reason)")
            sendNotification(
                title: "MEI: Deferred",
                body: "\(message.displayName): \(reason)"
            )
            return
        case .kill:
            appState.mode = .killed
            stop()
            return
        case .proceed:
            break
        }

        let isShadow = appState.mode == .shadow ||
            appState.contactMode(for: message.contactID) == .shadowOnly

        do {
            // 2. Embed incoming message for RAG search
            var ragChunks: [RAGChunk] = []
            do {
                let embedding = try await geminiEmbedding.embed(text: message.text)
                ragChunks = try ragDatabase.searchSimilar(
                    embedding: embedding,
                    contact: message.contactID,
                    limit: 8
                )
            } catch {
                print("[MEI] RAG search failed (continuing without): \(error)")
            }

            // 3. Load style profile
            let style = loadStyleProfile(for: message.contactID)

            // 4. Get conversation history
            let history = try await messageReader.fetchRecentMessages(
                chatIdentifier: message.chatID,
                limit: 20
            )

            // 5. Build prompt
            let prompt = PromptBuilder.build(
                message: message,
                ragResults: ragChunks,
                styleProfile: style,
                conversationHistory: history,
                restrictedTopics: appState.restrictedTopics
            )

            // 6. Call Gemini
            let rawResponse = try await geminiClient.generate(
                systemPrompt: prompt,
                userMessage: ""
            )

            let response = AgentResponse(rawText: rawResponse)

            // 7. Check response safety
            let responseCheck = SafetyChecks.checkResponse(
                response: response,
                threshold: appState.confidenceThreshold
            )

            switch responseCheck {
            case .defer(let reason):
                logExchange(
                    message: message,
                    response: response,
                    wasSent: false,
                    wasShadow: isShadow,
                    delay: 0,
                    ragChunks: ragChunks.map(\.id)
                )
                sendNotification(
                    title: "MEI: Needs your attention",
                    body: "\(message.displayName): \(reason)"
                )
                appState.todayMessagesDeferred += 1
                return
            case .skip, .kill:
                return
            case .proceed:
                break
            }

            // 8. Calculate reply delay
            let delay = BehaviorEngine.sampleReplyDelay(for: style)

            if isShadow {
                // Shadow mode: log but don't send
                logExchange(
                    message: message,
                    response: response,
                    wasSent: false,
                    wasShadow: true,
                    delay: delay,
                    ragChunks: ragChunks.map(\.id)
                )
                appState.todayMessagesShadow += 1
                print("[MEI] Shadow (\(message.displayName)): \(response.messages.joined(separator: " ||| "))")
                return
            }

            // 9. Wait for reply delay
            try await Task.sleep(for: .seconds(delay))

            // 10. Re-check if user started typing during delay
            if let isActive = try? await messageReader.hasRecentOutgoingMessage(
                chatIdentifier: message.chatID,
                withinSeconds: 60
            ), isActive {
                print("[MEI] User started typing during delay, aborting")
                return
            }

            // 11. Send messages
            for (index, msgText) in response.messages.enumerated() {
                try await messageSender.sendToChat(msgText, chatIdentifier: message.chatID)

                if index < response.messages.count - 1 {
                    let burstDelay = BehaviorEngine.burstDelay()
                    try await Task.sleep(for: .seconds(burstDelay))
                }
            }

            // 12. Log
            logExchange(
                message: message,
                response: response,
                wasSent: true,
                wasShadow: false,
                delay: delay,
                ragChunks: ragChunks.map(\.id)
            )
            appState.todayMessagesSent += 1
            print("[MEI] Sent to \(message.displayName): \(response.messages.joined(separator: " ||| "))")

        } catch {
            print("[MEI] Error processing message from \(message.displayName): \(error)")
            sendNotification(
                title: "MEI: Error",
                body: "Failed to process message from \(message.displayName)"
            )
        }
    }

    // MARK: - Helpers

    private func loadStyleProfile(for contactID: String) -> StyleProfile? {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("MEI/styles")

        // Try loading by contact ID (sanitized filename)
        let sanitized = contactID
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()

        let filePath = supportDir.appendingPathComponent("\(sanitized).json")

        guard let data = try? Data(contentsOf: filePath) else {
            // Try loading all profiles and matching
            return loadStyleProfileBySearch(contactID: contactID, directory: supportDir)
        }

        return try? JSONDecoder().decode(StyleProfile.self, from: data)
    }

    private func loadStyleProfileBySearch(contactID: String, directory: URL) -> StyleProfile? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return nil }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let profile = try? JSONDecoder().decode(StyleProfile.self, from: data) else {
                continue
            }
            if profile.phone == contactID || profile.contact.lowercased() == contactID.lowercased() {
                return profile
            }
        }
        return nil
    }

    private func logExchange(
        message: ChatMessage,
        response: AgentResponse,
        wasSent: Bool,
        wasShadow: Bool,
        delay: TimeInterval,
        ragChunks: [String]
    ) {
        let exchange = AgentExchange(
            id: Int64(Date().timeIntervalSince1970 * 1000),
            timestamp: Date(),
            contact: message.displayName,
            incomingText: message.text,
            generatedText: response.messages.joined(separator: " ||| "),
            confidence: response.confidence,
            wasSent: wasSent,
            wasShadow: wasShadow,
            replyDelaySeconds: delay,
            ragChunksUsed: ragChunks
        )

        appState.recentExchanges.insert(exchange, at: 0)
        if appState.recentExchanges.count > 100 {
            appState.recentExchanges = Array(appState.recentExchanges.prefix(100))
        }

        agentLog.logExchange(exchange)
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
