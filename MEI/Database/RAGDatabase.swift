import Foundation
import SQLite3
import Accelerate

final class RAGDatabase: @unchecked Sendable {
    private var db: OpaquePointer?

    private var dbPath: URL {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("MEI")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        return supportDir.appendingPathComponent("rag.db")
    }

    func open() throws {
        let path = dbPath.path
        let result = sqlite3_open(path, &db)
        guard result == SQLITE_OK else {
            throw RAGDatabaseError.cannotOpen(code: result)
        }
        try createTablesIfNeeded()
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    private func createTablesIfNeeded() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                contact TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                message_count INTEGER,
                is_group_chat BOOLEAN DEFAULT FALSE,
                chunk_text TEXT NOT NULL,
                topics TEXT,
                embedding BLOB NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_chunks_contact ON chunks(contact);
            CREATE INDEX IF NOT EXISTS idx_chunks_timestamp ON chunks(timestamp);
        """

        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let msg = error.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(error)
            throw RAGDatabaseError.queryFailed(message: msg)
        }
    }

    /// Search for similar chunks using brute-force cosine similarity with
    /// recency weighting and minimum similarity filtering.
    func searchSimilar(
        embedding: [Float],
        contact: String,
        limit: Int = 8,
        minSimilarity: Float = 0.4
    ) throws -> [RAGChunk] {
        guard let db = db else { throw RAGDatabaseError.notOpen }

        let query = """
            SELECT id, contact, timestamp, message_count, is_group_chat, chunk_text, topics, embedding
            FROM chunks
            WHERE contact = ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw RAGDatabaseError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (contact as NSString).utf8String, -1, nil)

        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        var results: [(chunk: RAGChunk, score: Float)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnText(stmt, 0) ?? ""
            let chunkContact = columnText(stmt, 1) ?? ""
            let timestampStr = columnText(stmt, 2) ?? ""
            let messageCount = Int(sqlite3_column_int(stmt, 3))
            let isGroup = sqlite3_column_int(stmt, 4) == 1
            let chunkText = columnText(stmt, 5) ?? ""
            let topicsJSON = columnText(stmt, 6) ?? "[]"

            // Read embedding blob
            guard let blob = sqlite3_column_blob(stmt, 7) else { continue }
            let blobSize = Int(sqlite3_column_bytes(stmt, 7))
            let floatCount = blobSize / MemoryLayout<Float>.size
            guard floatCount == 768 else { continue }

            let chunkEmbedding = Array(UnsafeBufferPointer(
                start: blob.assumingMemoryBound(to: Float.self),
                count: floatCount
            ))

            let similarity = cosineSimilarity(embedding, chunkEmbedding)

            // Filter out chunks below minimum similarity threshold
            guard similarity >= minSimilarity else { continue }

            let topics = (try? JSONDecoder().decode([String].self, from: topicsJSON.data(using: .utf8) ?? Data())) ?? []
            let timestamp = isoFormatter.date(from: timestampStr) ?? Date()

            // Apply recency weighting: recent chunks get a boost, old ones decay gently
            let ageInDays = Float(max(1, now.timeIntervalSince(timestamp) / 86400))
            let recencyBoost: Float = 1.0 / (1.0 + log(ageInDays / 7.0))
            let adjustedScore = similarity * 0.7 + similarity * recencyBoost * 0.3

            let chunk = RAGChunk(
                id: id,
                contact: chunkContact,
                timestamp: timestamp,
                messageCount: messageCount,
                isGroupChat: isGroup,
                chunkText: chunkText,
                topics: topics,
                embedding: chunkEmbedding,
                distance: 1 - similarity
            )

            results.append((chunk, adjustedScore))
        }

        // Sort by recency-weighted score descending, take top N
        return results
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.chunk)
    }

    func insertChunk(_ chunk: RAGChunk) throws {
        guard let db = db else { throw RAGDatabaseError.notOpen }

        let sql = """
            INSERT OR REPLACE INTO chunks (id, contact, timestamp, message_count, is_group_chat, chunk_text, topics, embedding)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RAGDatabaseError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (chunk.id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (chunk.contact as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (ISO8601DateFormatter().string(from: chunk.timestamp) as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 4, Int32(chunk.messageCount))
        sqlite3_bind_int(stmt, 5, chunk.isGroupChat ? 1 : 0)
        sqlite3_bind_text(stmt, 6, (chunk.chunkText as NSString).utf8String, -1, nil)

        let topicsJSON = (try? JSONEncoder().encode(chunk.topics)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        sqlite3_bind_text(stmt, 7, (topicsJSON as NSString).utf8String, -1, nil)

        chunk.embedding.withUnsafeBufferPointer { buffer in
            sqlite3_bind_blob(stmt, 8, buffer.baseAddress, Int32(buffer.count * MemoryLayout<Float>.size), nil)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RAGDatabaseError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    func chunkCount() -> Int {
        guard let db = db else { return 0 }
        let query = "SELECT COUNT(*) FROM chunks"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}

enum RAGDatabaseError: Error, LocalizedError {
    case cannotOpen(code: Int32)
    case notOpen
    case queryFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let code): return "Cannot open RAG database (error \(code))"
        case .notOpen: return "RAG database not open"
        case .queryFailed(let msg): return "RAG query failed: \(msg)"
        }
    }
}
