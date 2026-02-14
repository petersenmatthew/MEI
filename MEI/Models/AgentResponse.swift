import Foundation

struct AgentResponse: Sendable {
    let rawText: String
    let messages: [String]    // split on ||| for multi-message bursts
    let confidence: Double
    let isLowConfidence: Bool

    init(rawText: String) {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var confidence: Double = 0.9
        var isLow = false

        if text.hasPrefix("CONFIDENCE:LOW") {
            isLow = true
            confidence = 0.3
            text = text.replacingOccurrences(of: "CONFIDENCE:LOW", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        self.rawText = rawText
        self.messages = text.components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.confidence = confidence
        self.isLowConfidence = isLow
    }
}
