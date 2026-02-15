import Foundation
import SQLite3

actor MessageReader {
    private let chatDBPath: String
    private var db: OpaquePointer?
    private var lastProcessedRowID: Int64 = 0

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.chatDBPath = "\(home)/Library/Messages/chat.db"
    }

    func open() throws {
        guard FileManager.default.fileExists(atPath: chatDBPath) else {
            throw MessageReaderError.databaseNotFound
        }

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(chatDBPath, &db, flags, nil)
        guard result == SQLITE_OK else {
            throw MessageReaderError.cannotOpen(code: result)
        }
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    func setLastProcessedRowID(_ rowID: Int64) {
        lastProcessedRowID = rowID
    }

    func getLastProcessedRowID() -> Int64 {
        return lastProcessedRowID
    }

    func fetchNewMessages() throws -> [ChatMessage] {
        guard let db = db else { throw MessageReaderError.notOpen }

        let query = """
            SELECT
                m.ROWID,
                m.guid,
                m.text,
                m.is_from_me,
                m.date,
                m.attributedBody,
                m.cache_has_attachments,
                c.chat_identifier,
                c.display_name,
                c.style
            FROM message m
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE m.ROWID > ?
            ORDER BY m.ROWID ASC
            LIMIT 50
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw MessageReaderError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, lastProcessedRowID)

        var messages: [ChatMessage] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(stmt, 0)

            let guid = columnText(stmt, index: 1) ?? ""

            // Try text column first, fall back to attributedBody
            var text = columnText(stmt, index: 2)
            if text == nil || text?.isEmpty == true {
                text = extractTextFromAttributedBody(stmt, index: 5)
            }
            guard let messageText = text, !messageText.isEmpty else {
                lastProcessedRowID = rowID
                continue
            }

            let isFromMe = sqlite3_column_int(stmt, 3) == 1
            let dateValue = sqlite3_column_int64(stmt, 4)
            let hasAttachment = sqlite3_column_int(stmt, 6) == 1
            let chatIdentifier = columnText(stmt, index: 7) ?? ""
            let displayName = columnText(stmt, index: 8)
            let chatStyle = sqlite3_column_int(stmt, 9) // 43 = group, 45 = individual

            // Convert macOS Messages date (nanoseconds since 2001-01-01) to Date
            let date = dateFromChatDB(dateValue)

            // Extract contact ID from chat identifier
            let contactID = extractContactID(from: chatIdentifier)

            let message = ChatMessage(
                id: rowID,
                guid: guid,
                text: messageText,
                isFromMe: isFromMe,
                date: date,
                contactID: contactID,
                contactName: displayName,
                chatID: chatIdentifier,
                isGroupChat: chatStyle == 43,
                hasAttachment: hasAttachment
            )

            messages.append(message)
            lastProcessedRowID = rowID
        }

        return messages
    }

    func fetchRecentMessages(chatIdentifier: String, limit: Int = 20) throws -> [ChatMessage] {
        guard let db = db else { throw MessageReaderError.notOpen }

        let query = """
            SELECT
                m.ROWID,
                m.guid,
                m.text,
                m.is_from_me,
                m.date,
                m.attributedBody,
                m.cache_has_attachments,
                c.chat_identifier,
                c.display_name,
                c.style
            FROM message m
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE c.chat_identifier = ?
            ORDER BY m.date DESC
            LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw MessageReaderError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (chatIdentifier as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var messages: [ChatMessage] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(stmt, 0)
            let guid = columnText(stmt, index: 1) ?? ""

            var text = columnText(stmt, index: 2)
            if text == nil || text?.isEmpty == true {
                text = extractTextFromAttributedBody(stmt, index: 5)
            }
            guard let messageText = text, !messageText.isEmpty else { continue }

            let isFromMe = sqlite3_column_int(stmt, 3) == 1
            let dateValue = sqlite3_column_int64(stmt, 4)
            let hasAttachment = sqlite3_column_int(stmt, 6) == 1
            let chatIdentifier = columnText(stmt, index: 7) ?? ""
            let displayName = columnText(stmt, index: 8)
            let chatStyle = sqlite3_column_int(stmt, 9)

            let date = dateFromChatDB(dateValue)
            let contactID = extractContactID(from: chatIdentifier)

            messages.append(ChatMessage(
                id: rowID,
                guid: guid,
                text: messageText,
                isFromMe: isFromMe,
                date: date,
                contactID: contactID,
                contactName: displayName,
                chatID: chatIdentifier,
                isGroupChat: chatStyle == 43,
                hasAttachment: hasAttachment
            ))
        }

        return messages.reversed() // chronological order
    }

    func getMaxRowID() throws -> Int64 {
        guard let db = db else { throw MessageReaderError.notOpen }

        let query = "SELECT MAX(ROWID) FROM message"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw MessageReaderError.queryFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return 0
    }

    /// Check if the real user (not MEI) has sent an outgoing message recently.
    /// `afterDate` allows filtering out MEI's own sends — only counts outgoing messages after that date.
    func hasRecentOutgoingMessage(
        chatIdentifier: String,
        withinSeconds: TimeInterval = 60,
        afterDate: Date? = nil
    ) throws -> Bool {
        guard let db = db else { throw MessageReaderError.notOpen }

        let cutoff = Date().addingTimeInterval(-withinSeconds)
        // Use the later of cutoff or afterDate so we ignore MEI's own messages
        let effectiveCutoff = if let afterDate = afterDate {
            max(cutoff, afterDate)
        } else {
            cutoff
        }
        let cutoffNano = Int64(effectiveCutoff.timeIntervalSinceReferenceDate * 1_000_000_000)

        let query = """
            SELECT COUNT(*) FROM message m
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE c.chat_identifier = ?
            AND m.is_from_me = 1
            AND m.date > ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (chatIdentifier as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, cutoffNano)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0) > 0
        }
        return false
    }

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func extractTextFromAttributedBody(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let blob = sqlite3_column_blob(stmt, index) else { return nil }
        let length = sqlite3_column_bytes(stmt, index)
        guard length > 0 else { return nil }

        let data = Data(bytes: blob, count: Int(length))

        // attributedBody is an NSKeyedArchiver plist. Try to extract plain text.
        if let unarchived = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSAttributedString.self, from: data
        ) {
            return unarchived.string
        }

        // Fallback: look for the text in the raw bytes using a simple heuristic
        if let str = String(data: data, encoding: .utf8) {
            // Find text between known markers
            let cleaned = str.components(separatedBy: .controlCharacters).joined()
            return cleaned.isEmpty ? nil : cleaned
        }

        return nil
    }

    private func dateFromChatDB(_ value: Int64) -> Date {
        // chat.db stores dates as nanoseconds since 2001-01-01 (Core Data reference date)
        let seconds = Double(value) / 1_000_000_000.0
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private func extractContactID(from chatIdentifier: String) -> String {
        // chat_identifier format: "iMessage;-;+11234567890" or "iMessage;-;email@example.com"
        let parts = chatIdentifier.components(separatedBy: ";")
        return parts.last ?? chatIdentifier
    }
}

enum MessageReaderError: Error, LocalizedError {
    case databaseNotFound
    case cannotOpen(code: Int32)
    case notOpen
    case queryFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "chat.db not found. Grant Full Disk Access in System Settings > Privacy & Security."
        case .cannotOpen(let code):
            return "Cannot open chat.db (error \(code)). Check Full Disk Access permission."
        case .notOpen:
            return "Database not opened. Call open() first."
        case .queryFailed(let message):
            return "Query failed: \(message)"
        }
    }
}
