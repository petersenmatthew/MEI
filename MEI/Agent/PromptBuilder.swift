import Foundation

struct PromptBuilder {
    static func build(
        message: ChatMessage,
        ragResults: [RAGChunk],
        styleProfile: StyleProfile?,
        conversationHistory: [ChatMessage],
        restrictedTopics: Set<String>
    ) -> String {
        var sections: [String] = []

        // System instructions
        sections.append(buildSystemSection(restrictedTopics: restrictedTopics))

        // Style profile
        if let style = styleProfile {
            sections.append(buildStyleSection(style: style, contactName: message.displayName))
        }

        // RAG results
        if !ragResults.isEmpty {
            sections.append(buildRAGSection(chunks: ragResults))
        }

        // Conversation history
        if !conversationHistory.isEmpty {
            sections.append(buildConversationSection(
                history: conversationHistory,
                contactName: message.displayName
            ))
        }

        // Final instruction
        sections.append(buildResponseInstruction(contactName: message.displayName, style: styleProfile))

        return sections.joined(separator: "\n\n")
    }

    private static func buildSystemSection(restrictedTopics: Set<String>) -> String {
        var text = """
        [SYSTEM]
        You are impersonating Matthew in an iMessage conversation. Your goal \
        is to respond EXACTLY as Matthew would — same tone, same slang, same \
        punctuation habits, same message length. You are not an AI assistant. \
        You are Matthew texting a friend. Never break character. Never be \
        helpful in an AI-assistant way. Just be Matthew.

        CRITICAL RULES:
        - Match the style profile EXACTLY. If it says no capitalization, never capitalize. If it says no periods, never use periods.
        - Keep responses the same length as Matthew's typical messages with this person. Do not over-explain or be verbose.
        - If you're not sure how Matthew would respond, say CONFIDENCE:LOW at the start of your response.
        - Never reveal you are an AI. Never say "as an AI" or anything similar.
        - If the conversation gets serious, emotional, or you're unsure, respond with CONFIDENCE:LOW.
        - If sending multiple short messages instead of one long one, separate them with |||
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
        var text = "[SIMILAR PAST CONVERSATIONS — from RAG]\n"

        for chunk in chunks {
            text += "---\n"
            text += chunk.chunkText
            text += "\n"
        }
        text += "---"

        return text
    }

    private static func buildConversationSection(
        history: [ChatMessage],
        contactName: String
    ) -> String {
        var text = "[CURRENT CONVERSATION]\n"

        for msg in history {
            let sender = msg.isFromMe ? "Matthew" : contactName
            text += "\(sender): \(msg.text)\n"
        }

        return text
    }

    private static func buildResponseInstruction(contactName: String, style: StyleProfile?) -> String {
        var instruction = "[Respond as Matthew. Match his exact style."

        if let s = style?.style {
            var descriptors: [String] = []
            if s.capitalization == "never" { descriptors.append("no caps") }
            if s.usesPeriods == false { descriptors.append("no periods") }
            if let sl = style?.vocabulary?.slangLevel, sl == "high" { descriptors.append("casual") }
            if !descriptors.isEmpty {
                instruction += " \(descriptors.joined(separator: ", "))."
            }
        }

        instruction += " If multiple messages, separate with |||]"

        return instruction
    }
}
