import Foundation

struct RAGChunk: Identifiable, Sendable {
    let id: String
    let contact: String
    let timestamp: Date
    let messageCount: Int
    let isGroupChat: Bool
    let chunkText: String
    let topics: [String]
    let embedding: [Float]
    let distance: Float?  // similarity distance from query, populated during search
}
