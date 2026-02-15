import Foundation

struct SafetyChecks {
    /// Check if the agent should process this message at all.
    /// `lastMEISendTime` is when MEI last sent to this chat, so we can ignore our own outgoing messages.
    static func shouldProcess(
        message: ChatMessage,
        appState: AppState,
        messageReader: MessageReader,
        lastMEISendTime: Date? = nil
    ) async -> SafetyResult {
        // Skip our own messages
        guard !message.isFromMe else {
            return .skip(reason: "Own message")
        }

        // Skip group chats (MVP)
        guard !message.isGroupChat else {
            return .skip(reason: "Group chat")
        }

        // Check agent mode
        guard appState.shouldProcess else {
            return .skip(reason: "Agent paused or killed")
        }

        // Check active hours
        guard appState.isWithinActiveHours else {
            return .skip(reason: "Outside active hours")
        }

        // Check contact mode
        let contactMode = appState.contactMode(for: message.contactID)
        switch contactMode {
        case .blacklist:
            return .skip(reason: "Contact blacklisted")
        case .whitelist:
            return .skip(reason: "Contact on whitelist but not active")
        case .active, .shadowOnly:
            break
        }

        // Check if user is actively texting this person (ignore MEI's own sends)
        if let isActive = try? await messageReader.hasRecentOutgoingMessage(
            chatIdentifier: message.chatID,
            withinSeconds: 60,
            afterDate: lastMEISendTime
        ), isActive {
            return .defer(reason: "User is actively texting this contact")
        }

        // Check kill word
        if !appState.killWord.isEmpty &&
            message.text.lowercased().contains(appState.killWord.lowercased()) {
            return .kill(reason: "Kill word detected")
        }

        return .proceed
    }

    /// Check the agent's response before sending.
    static func checkResponse(
        response: AgentResponse,
        threshold: Double
    ) -> SafetyResult {
        if response.isLowConfidence || response.confidence < threshold {
            return .defer(reason: "Low confidence (\(String(format: "%.2f", response.confidence)))")
        }

        if response.messages.isEmpty {
            return .skip(reason: "Empty response")
        }

        // Check for common AI-sounding phrases
        let aiPhrases = [
            "as an ai", "i'm an ai", "i am an ai",
            "language model", "i don't have feelings",
            "i can help you with", "how can i assist",
            "i'd be happy to help"
        ]
        let lowered = response.rawText.lowercased()
        for phrase in aiPhrases {
            if lowered.contains(phrase) {
                return .defer(reason: "AI-sounding language detected")
            }
        }

        return .proceed
    }
}

enum SafetyResult {
    case proceed
    case skip(reason: String)
    case `defer`(reason: String)
    case kill(reason: String)
}
