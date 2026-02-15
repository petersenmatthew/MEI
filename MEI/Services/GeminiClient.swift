import Foundation

actor GeminiClient {
    private let model = "gemini-2.5-flash-lite"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    private var apiKey: String {
        KeychainManager.load(key: "gemini_api_key") ?? ""
    }

    struct GeminiRequest: Encodable {
        let system_instruction: SystemInstruction?
        let contents: [Content]
        let generationConfig: GenerationConfig?

        struct SystemInstruction: Encodable {
            let parts: [Part]
        }

        struct Content: Encodable {
            let role: String
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String
        }

        struct GenerationConfig: Encodable {
            let temperature: Double?
            let maxOutputTokens: Int?
            let topP: Double?
        }
    }

    struct GeminiResponse: Decodable {
        let candidates: [Candidate]?
        let error: GeminiError?

        struct Candidate: Decodable {
            let content: Content?

            struct Content: Decodable {
                let parts: [Part]?

                struct Part: Decodable {
                    let text: String?
                }
            }
        }

        struct GeminiError: Decodable {
            let message: String?
            let code: Int?
        }
    }

    struct ConversationTurn {
        let role: String  // "user" or "model"
        let text: String
    }

    func generate(
        systemPrompt: String,
        conversationHistory: [ConversationTurn],
        userMessage: String
    ) async throws -> String {
        let key = apiKey
        guard !key.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(key)")!

        // Build contents array from conversation history + final user message
        var contents: [GeminiRequest.Content] = conversationHistory.map { turn in
            .init(role: turn.role, parts: [.init(text: turn.text)])
        }

        // Add the final user message (the instruction to respond)
        if !userMessage.isEmpty {
            contents.append(.init(role: "user", parts: [.init(text: userMessage)]))
        }

        // Ensure contents is not empty
        if contents.isEmpty {
            contents.append(.init(role: "user", parts: [.init(text: "Hello")]))
        }

        let request = GeminiRequest(
            system_instruction: .init(parts: [.init(text: systemPrompt)]),
            contents: contents,
            generationConfig: .init(
                temperature: 0.9,
                maxOutputTokens: 1024,
                topP: 0.95
            )
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.httpError(status: httpResponse.statusCode, body: body)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        if let error = geminiResponse.error {
            throw GeminiError.apiError(message: error.message ?? "Unknown error")
        }

        guard let text = geminiResponse.candidates?.first?.content?.parts?.first?.text else {
            throw GeminiError.noContent
        }

        return text
    }
}

enum GeminiError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(status: Int, body: String)
    case apiError(message: String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Gemini API key configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .httpError(let status, let body):
            return "Gemini API error (HTTP \(status)): \(body.prefix(200))"
        case .apiError(let message):
            return "Gemini API error: \(message)"
        case .noContent:
            return "Gemini returned no content"
        }
    }
}
