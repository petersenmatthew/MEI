import Foundation

struct BuiltPrompt {
    let systemInstruction: String
    let conversationTurns: [GeminiClient.ConversationTurn]
    let finalUserMessage: String
}

struct PromptBuilder {
    static func build(
        message: ChatMessage,
        ragResults: [RAGChunk],
        styleProfile: StyleProfile?,
        conversationHistory: [ChatMessage],
        restrictedTopics: Set<String>,
        alwaysRespond: Bool = false,
        fewShotExamples: [(incoming: String, generated: String, confidence: Double)] = []
    ) -> BuiltPrompt {
        // --- System instruction (goes into Gemini's system_instruction field) ---
        var systemParts: [String] = []
        systemParts.append(buildSystemSection(restrictedTopics: restrictedTopics, alwaysRespond: alwaysRespond))

        // Message type-specific guidance
        systemParts.append(buildMessageTypeGuidance(for: message))

        if let style = styleProfile {
            systemParts.append(buildStyleSection(style: style, contactName: message.displayName))
        }

        if !fewShotExamples.isEmpty {
            systemParts.append(buildFewShotSection(examples: fewShotExamples, contactName: message.displayName))
        }

        if !ragResults.isEmpty {
            systemParts.append(buildRAGSection(chunks: ragResults))
        }

        let systemInstruction = systemParts.joined(separator: "\n\n")

        // --- Conversation history as proper multi-turn contents ---
        var turns: [GeminiClient.ConversationTurn] = []

        for msg in conversationHistory {
            let role = msg.isFromMe ? "model" : "user"
            turns.append(.init(role: role, text: msg.text))
        }

        // Merge consecutive same-role turns (Gemini requires alternating roles)
        turns = mergeConsecutiveTurns(turns)

        // --- Final user message: the new incoming message to reply to ---
        // Always send the triggering message as a separate final turn so Gemini
        // knows exactly which message to reply to. When multiple consecutive
        // user messages get merged into one turn, the model can't tell which
        // is the latest — so we split it out explicitly.

        // Remove the triggering message text from the last user turn to avoid
        // sending it twice (once in history, once as the final message).
        if let lastIndex = turns.indices.last, turns[lastIndex].role == "user" {
            let cleaned = turns[lastIndex].text
                .replacingOccurrences(of: message.text, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                // The triggering message was the only content — remove the turn entirely
                turns.removeLast()
            } else {
                // Keep the remaining history text
                turns[lastIndex] = .init(role: "user", text: cleaned)
            }
            // If the last turn is now "user", Gemini needs alternating roles,
            // so insert a placeholder model turn before our final user message.
            if turns.last?.role == "user" {
                turns.append(.init(role: "model", text: "(no reply yet)"))
            }
        }

        let finalMessage = message.text

        return BuiltPrompt(
            systemInstruction: systemInstruction,
            conversationTurns: turns,
            finalUserMessage: finalMessage
        )
    }

    /// Merge consecutive turns with the same role by joining their text.
    /// Gemini API requires alternating user/model roles.
    private static func mergeConsecutiveTurns(
        _ turns: [GeminiClient.ConversationTurn]
    ) -> [GeminiClient.ConversationTurn] {
        guard !turns.isEmpty else { return [] }

        var merged: [GeminiClient.ConversationTurn] = []
        var currentRole = turns[0].role
        var currentTexts = [turns[0].text]

        for turn in turns.dropFirst() {
            if turn.role == currentRole {
                currentTexts.append(turn.text)
            } else {
                merged.append(.init(role: currentRole, text: currentTexts.joined(separator: "\n")))
                currentRole = turn.role
                currentTexts = [turn.text]
            }
        }
        merged.append(.init(role: currentRole, text: currentTexts.joined(separator: "\n")))

        // Gemini requires the first turn to be "user". If it starts with "model", prepend a placeholder.
        if merged.first?.role == "model" {
            merged.insert(.init(role: "user", text: "(conversation start)"), at: 0)
        }

        return merged
    }

    private static func buildSystemSection(restrictedTopics: Set<String>, alwaysRespond: Bool) -> String {
        var text = """
        You are impersonating Matthew in an iMessage conversation. Your goal \
        is to respond EXACTLY as Matthew would — same tone, same slang, same \
        punctuation habits, same message length. You are not an AI assistant. \
        You are Matthew texting a friend. Never break character. Never be \
        helpful in an AI-assistant way. Just be Matthew.

        CRITICAL RULES:
        - Match the message length, tone, and style described in the style profile below. If no style profile is provided, default to short casual texts.
        - Reply directly to what was just said to you. Stay on topic.
        """

        if alwaysRespond {
            text += """
            - Always respond to every message. Do your best to match Matthew's style even if unsure.
            - Never reveal you are an AI. Never say "as an AI" or anything similar.
            - If sending multiple short messages instead of one long one, separate them with |||
            - Follow the capitalization, punctuation, and formatting patterns from the style profile below. If no style profile is provided, default to lowercase casual texting.
            - Do NOT include any prefix like "Matthew:" in your response. Just write the message text directly.
            """
        } else {
            text += """
            - Before your message, output a confidence line in this exact format: CONF:0.85
              Where the number is 0.0-1.0 indicating how confident you are this sounds like Matthew.
              0.9+ = very confident, sounds exactly like Matthew
              0.7-0.9 = confident, good match
              0.5-0.7 = uncertain, might sound off
              Below 0.5 = very unsure, risky to send
              Then write your message on the next line.
            - If the conversation is serious, emotional, or about sensitive topics, lower your confidence score.
            - Never reveal you are an AI. Never say "as an AI" or anything similar.
            - If sending multiple short messages instead of one long one, separate them with |||
            - Follow the capitalization, punctuation, and formatting patterns from the style profile below. If no style profile is provided, default to lowercase casual texting.
            - Do NOT include any prefix like "Matthew:" in your response. Just the CONF line then the message.
            """
        }

        if !restrictedTopics.isEmpty {
            if alwaysRespond {
                text += "\n- Avoid these topics if possible, but still respond with something: \(restrictedTopics.joined(separator: ", "))"
            } else {
                text += "\n- For these restricted topics, set your confidence below 0.3: \(restrictedTopics.joined(separator: ", "))"
            }
        }

        return text
    }

    private static func buildStyleSection(style: StyleProfile, contactName: String) -> String {
        return """
        [STYLE PROFILE — \(contactName)]
        \(style.toPromptSection())
        """
    }

    // MARK: - Message Type Detection

    private enum MessageType {
        case greeting, question, emojiOnly, emotional, shortCasual, linkOrMedia, normal
    }

    private static func classifyMessage(_ message: ChatMessage) -> MessageType {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Emoji-only: all characters are emoji/whitespace
        let strippedEmoji = text.unicodeScalars.filter { !$0.properties.isEmoji && !$0.properties.isEmojiPresentation && !CharacterSet.whitespaces.contains($0) }
        if strippedEmoji.isEmpty && !text.isEmpty { return .emojiOnly }

        // Link/media
        if text.contains("http://") || text.contains("https://") || message.hasAttachment { return .linkOrMedia }

        // Greeting
        let greetings = ["hey", "hi", "hello", "yo", "sup", "what's up", "whats up", "wassup", "wsg", "heyy", "heyyy"]
        if greetings.contains(where: { text.hasPrefix($0) }) && text.count < 25 { return .greeting }

        // Question
        if text.contains("?") { return .question }

        // Emotional/serious
        let emotionalWords = ["worried", "miss you", "rough day", "stressed", "depressed", "sad", "crying", "hurt", "sorry", "love you", "passed away", "died", "funeral", "hospital", "emergency"]
        if emotionalWords.contains(where: { text.contains($0) }) { return .emotional }

        // Short casual
        if text.count < 15 { return .shortCasual }

        return .normal
    }

    private static func buildMessageTypeGuidance(for message: ChatMessage) -> String {
        switch classifyMessage(message) {
        case .greeting:
            return "[CONTEXT: This is a greeting. Match Matthew's typical greeting style — keep it casual and brief.]"
        case .question:
            return "[CONTEXT: They asked a question. Answer directly and stay on topic. Match Matthew's typical response length for questions.]"
        case .emojiOnly:
            return "[CONTEXT: They sent just emoji. Respond with a very short reaction — emoji, a few words, or a brief acknowledgment. Don't over-respond.]"
        case .emotional:
            return "[CONTEXT: This seems emotional or serious. Be genuine and empathetic but still sound like Matthew. Don't be overly formal or therapeutic.]"
        case .shortCasual:
            return "[CONTEXT: Short casual message. Match their energy — keep your reply similarly brief.]"
        case .linkOrMedia:
            return "[CONTEXT: They shared a link or media. React naturally — acknowledge it, comment on it, or ask about it.]"
        case .normal:
            return ""
        }
    }

    private static func buildFewShotSection(examples: [(incoming: String, generated: String, confidence: Double)], contactName: String) -> String {
        var text = "[EXAMPLES OF MATTHEW'S PAST REPLIES TO \(contactName.uppercased())]\n"
        text += "These are real replies Matthew sent that matched his style well. Use them as tone/style reference.\n\n"
        for example in examples {
            text += "They said: \"\(example.incoming)\"\n"
            text += "Matthew replied: \"\(example.generated)\"\n\n"
        }
        return text
    }

    private static func buildRAGSection(chunks: [RAGChunk]) -> String {
        var text = """
        [SIMILAR PAST CONVERSATIONS]
        These are past conversations with this contact, ranked by relevance.
        Use them as reference for tone, vocabulary, and how Matthew handles similar topics.
        More recent and higher-relevance conversations are more reliable references.

        """

        for (i, chunk) in chunks.enumerated() {
            let dateStr = relativeDate(chunk.timestamp)
            let similarity = chunk.distance.map { String(format: "%.0f%%", (1 - $0) * 100) } ?? "?"
            let topicStr = chunk.topics.isEmpty ? "" : " | Topics: \(chunk.topics.joined(separator: ", "))"
            text += "--- Conversation \(i + 1) (relevance: \(similarity), \(dateStr)\(topicStr)) ---\n"
            text += chunk.chunkText
            text += "\n"
        }
        text += "---"

        return text
    }

    private static func relativeDate(_ date: Date) -> String {
        let days = Int(-date.timeIntervalSinceNow / 86400)
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        if days < 30 { return "\(days / 7) weeks ago" }
        if days < 365 { return "\(days / 30) months ago" }
        return "\(days / 365) years ago"
    }
}
