import Foundation
import SwiftUI

enum AgentMode: String, CaseIterable, Sendable {
    case active = "Active"
    case shadow = "Shadow"
    case paused = "Paused"
    case killed = "Killed"

    var icon: String {
        switch self {
        case .active: return "circle.fill"
        case .shadow: return "eye.fill"
        case .paused: return "pause.circle.fill"
        case .killed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .shadow: return .yellow
        case .paused: return .red
        case .killed: return .gray
        }
    }
}

enum ContactMode: String, Codable, CaseIterable, Sendable {
    case active = "Active"
    case shadowOnly = "Shadow Only"
    case whitelist = "Whitelist"
    case blacklist = "Blacklist"
}

struct ContactConfig: Codable, Identifiable, Sendable {
    var id: String { contactID }
    let contactID: String
    var displayName: String
    var mode: ContactMode
    var customRules: [String]
}

struct AgentExchange: Identifiable, Sendable {
    let id: Int64
    let timestamp: Date
    let contact: String
    let incomingText: String
    let generatedText: String
    let confidence: Double
    let wasSent: Bool
    let wasShadow: Bool
    let replyDelaySeconds: Double
    let ragChunksUsed: [String]
    var userFeedback: String?
    var actualReply: String?  // what user actually said (shadow mode)
    var matchScore: Double?   // shadow mode match %
}

@MainActor
@Observable
final class AppState {
    var mode: AgentMode = .paused
    var confidenceThreshold: Double = 0.2  // TODO: Restore to 0.75 before production
    var sendDelayEnabled: Bool = true
    var sendDelaySeconds: Int = 30
    var killWord: String = ""
    var activeHoursStart: Int = 8   // 8 AM
    var activeHoursEnd: Int = 23    // 11 PM

    var contacts: [ContactConfig] = [] {
        didSet { saveContacts() }
    }
    var recentExchanges: [AgentExchange] = []

    init() {
        loadContacts()
    }

    // Stats
    var todayMessagesSent: Int = 0
    var todayMessagesDeferred: Int = 0
    var todayMessagesShadow: Int = 0
    var todayAvgConfidence: Double = 0
    var monthlyCost: Double = 0

    // Restricted topics
    var restrictedTopics: Set<String> = [
        "Financial details",
        "Relationship drama",
        "Health/medical"
    ]

    var isWithinActiveHours: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= activeHoursStart && hour < activeHoursEnd
    }

    var shouldProcess: Bool {
        mode == .active || mode == .shadow
    }

    func contactMode(for contactID: String) -> ContactMode {
        contacts.first(where: { $0.contactID == contactID })?.mode ?? .active
    }

    // MARK: - Contact Persistence

    private static var contactsFileURL: URL {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("MEI")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        return supportDir.appendingPathComponent("contacts.json")
    }

    func loadContacts() {
        let url = Self.contactsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            contacts = try JSONDecoder().decode([ContactConfig].self, from: data)
        } catch {
            print("[AppState] Failed to load contacts: \(error)")
        }
    }

    private func saveContacts() {
        do {
            let data = try JSONEncoder().encode(contacts)
            try data.write(to: Self.contactsFileURL, options: .atomic)
        } catch {
            print("[AppState] Failed to save contacts: \(error)")
        }
    }
}
