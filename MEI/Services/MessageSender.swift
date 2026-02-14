import Foundation

actor MessageSender {
    func send(_ text: String, to recipient: String) async throws {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedRecipient = recipient
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            set targetBuddy to participant "\(escapedRecipient)" of targetService
            send "\(escapedText)" to targetBuddy
        end tell
        """

        try await runAppleScript(script)
    }

    func sendToChat(_ text: String, chatIdentifier: String) async throws {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Use the chat identifier to find the right conversation
        let script = """
        tell application "Messages"
            set targetChat to a reference to chat id "\(chatIdentifier)"
            send "\(escapedText)" to targetChat
        end tell
        """

        try await runAppleScript(script)
    }

    private func runAppleScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                script?.executeAndReturnError(&error)

                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: MessageSenderError.appleScriptFailed(message: message))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum MessageSenderError: Error, LocalizedError {
    case appleScriptFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .appleScriptFailed(let message):
            return "Failed to send message: \(message)"
        }
    }
}
