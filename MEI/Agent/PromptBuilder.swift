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
        restrictedTopics: Set<String>
    ) -> BuiltPrompt {
        // --- System instruction (goes into Gemini's system_instruction field) ---
        var systemParts: [String] = []
        systemParts.append(buildSystemSection(restrictedTopics: restrictedTopics))

        if let style = styleProfile {
            systemParts.append(buildStyleSection(style: style, contactName: message.displayName))
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

    private static func buildSystemSection(restrictedTopics: Set<String>) -> String {
        var text = """
        You are impersonating Matthew in an iMessage conversation. Your goal \
        is to respond EXACTLY as Matthew would — same tone, same slang, same \
        punctuation habits, same message length. You are not an AI assistant. \
        You are Matthew texting a friend. Never break character. Never be \
        helpful in an AI-assistant way. Just be Matthew.

        CRITICAL RULES:
        - Keep responses short and casual like a real text message. Do not over-explain or be verbose.
        - Reply directly to what was just said to you. Stay on topic.
        - If you're not sure how Matthew would respond, start your response with CONFIDENCE:LOW
        - Never reveal you are an AI. Never say "as an AI" or anything similar.
        - If the conversation gets serious, emotional, or you're unsure, respond with CONFIDENCE:LOW
        - If sending multiple short messages instead of one long one, separate them with |||
        - Use all lowercase, no periods, casual texting style
        - Do NOT include any prefix like "Matthew:" in your response. Just write the message text directly.
        """

        if !restrictedTopics.isEmpty {
            text += "\n- NEVER respond about these topics (respond with CONFIDENCE:LOW instead): \(restrictedTopics.joined(separator: ", "))"
        }

        return text
    }

    private static func buildStyleSection(style: StyleProfile, contactName: String) -> String {
        return """
        [STYLE PROFILE — \(contactName)]
        \(style.toPromptSection())
        """
    }

    private static func buildRAGSection(chunks: [RAGChunk]) -> String {
        var text = "[SIMILAR PAST CONVERSATIONS — use these as reference for how Matthew texts]\n"

        for chunk in chunks {
            text += "---\n"
            text += chunk.chunkText
            text += "\n"
        }
        text += "---"

        return text
    }
}
