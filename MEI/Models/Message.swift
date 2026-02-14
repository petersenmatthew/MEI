import Foundation

struct ChatMessage: Identifiable, Sendable {
    let id: Int64          // ROWID from chat.db
    let guid: String
    let text: String
    let isFromMe: Bool
    let date: Date
    let contactID: String  // phone number or email
    let contactName: String?
    let chatID: String     // chat identifier (e.g. "iMessage;-;+11234567890")
    let isGroupChat: Bool
    let hasAttachment: Bool

    var displayName: String {
        contactName ?? contactID
    }
}
