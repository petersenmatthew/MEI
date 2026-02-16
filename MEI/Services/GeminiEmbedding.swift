import Foundation

actor GeminiEmbedding {
    private let model = "gemini-embedding-001"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    private var apiKey: String {
        KeychainManager.load(key: "gemini_api_key") ?? ""
    }

    struct EmbedRequest: Encodable {
        let content: Content
        let output_dimensionality: Int?

        struct Content: Encodable {
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String
        }
    }

    struct EmbedResponse: Decodable {
        let embedding: EmbeddingValues?
        let error: ErrorDetail?

        struct EmbeddingValues: Decodable {
            let values: [Float]
        }

        struct ErrorDetail: Decodable {
            let message: String?
        }
    }

    func embed(text: String) async throws -> [Float] {
        let key = apiKey
        guard !key.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/models/\(model):embedContent?key=\(key)")!

        let request = EmbedRequest(
            content: .init(parts: [.init(text: text)]),
            output_dimensionality: 768
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.httpError(status: status, body: body)
        }

        let embedResponse = try JSONDecoder().decode(EmbedResponse.self, from: data)

        if let error = embedResponse.error {
            throw GeminiError.apiError(message: error.message ?? "Embedding error")
        }

        guard let values = embedResponse.embedding?.values, values.count == 768 else {
            throw GeminiError.noContent
        }

        return values
    }
}
