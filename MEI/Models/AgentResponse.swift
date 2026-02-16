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

        // Parse structured confidence: "CONF:0.85\nmessage text"
        if let match = text.range(of: #"^CONF:(\d+\.?\d*)"#, options: .regularExpression) {
            let numStr = String(text[match]).dropFirst(5) // drop "CONF:"
            if let parsed = Double(numStr) {
                confidence = min(1.0, max(0.0, parsed))
            }
            text = String(text[match.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            isLow = confidence < 0.5
        }
        // Backward compatibility: legacy CONFIDENCE:LOW prefix
        else if text.hasPrefix("CONFIDENCE:LOW") {
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
