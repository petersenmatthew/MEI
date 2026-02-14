import Foundation
import SQLite3

final class AgentLogDatabase: @unchecked Sendable {
    private var db: OpaquePointer?

    private var dbPath: URL {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("MEI")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        return supportDir.appendingPathComponent("agent_log.db")
    }

    func open() throws {
        let result = sqlite3_open(dbPath.path, &db)
        guard result == SQLITE_OK else {
            throw AgentLogError.cannotOpen(code: result)
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
            CREATE TABLE IF NOT EXISTS agent_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                contact TEXT NOT NULL,
                incoming_text TEXT NOT NULL,
                generated_text TEXT NOT NULL,
                confidence REAL,
                was_sent BOOLEAN,
                was_shadow BOOLEAN DEFAULT FALSE,
                reply_delay_seconds REAL,
                rag_chunks_used TEXT,
                user_feedback TEXT
            );

            CREATE TABLE IF NOT EXISTS sync_state (
                key TEXT PRIMARY KEY,
                value TEXT
            );
        """

        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let msg = error.map { String(cString: $0) } ?? "Unknown"
            sqlite3_free(error)
            throw AgentLogError.queryFailed(message: msg)
        }
    }

    func logExchange(_ exchange: AgentExchange) {
        guard let db = db else { return }

        let sql = """
            INSERT INTO agent_log (timestamp, contact, incoming_text, generated_text, confidence, was_sent, was_shadow, reply_delay_seconds, rag_chunks_used, user_feedback)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let ts = ISO8601DateFormatter().string(from: exchange.timestamp)
        sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (exchange.contact as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (exchange.incomingText as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (exchange.generatedText as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 5, exchange.confidence)
        sqlite3_bind_int(stmt, 6, exchange.wasSent ? 1 : 0)
        sqlite3_bind_int(stmt, 7, exchange.wasShadow ? 1 : 0)
        sqlite3_bind_double(stmt, 8, exchange.replyDelaySeconds)

        let chunksJSON = (try? JSONEncoder().encode(exchange.ragChunksUsed)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        sqlite3_bind_text(stmt, 9, (chunksJSON as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 10, nil, -1, nil)

        sqlite3_step(stmt)
    }

    func updateFeedback(exchangeID: Int64, feedback: String) {
        guard let db = db else { return }
        let sql = "UPDATE agent_log SET user_feedback = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (feedback as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, exchangeID)
        sqlite3_step(stmt)
    }

    func saveSyncState(key: String, value: String) {
        guard let db = db else { return }
        let sql = "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    func loadSyncState(key: String) -> String? {
        guard let db = db else { return nil }
        let sql = "SELECT value FROM sync_state WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
            return String(cString: cStr)
        }
        return nil
    }

    func fetchStats(since: Date) -> (sent: Int, deferred: Int, shadow: Int, avgConfidence: Double) {
        guard let db = db else { return (0, 0, 0, 0) }
        let ts = ISO8601DateFormatter().string(from: since)

        let sql = """
            SELECT
                SUM(CASE WHEN was_sent = 1 THEN 1 ELSE 0 END),
                SUM(CASE WHEN was_sent = 0 AND was_shadow = 0 THEN 1 ELSE 0 END),
                SUM(CASE WHEN was_shadow = 1 THEN 1 ELSE 0 END),
                AVG(confidence)
            FROM agent_log WHERE timestamp >= ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (0, 0, 0, 0) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return (
                sent: Int(sqlite3_column_int(stmt, 0)),
                deferred: Int(sqlite3_column_int(stmt, 1)),
                shadow: Int(sqlite3_column_int(stmt, 2)),
                avgConfidence: sqlite3_column_double(stmt, 3)
            )
        }
        return (0, 0, 0, 0)
    }
}

enum AgentLogError: Error, LocalizedError {
    case cannotOpen(code: Int32)
    case queryFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let code): return "Cannot open agent log (error \(code))"
        case .queryFailed(let msg): return "Agent log query failed: \(msg)"
        }
    }
}
