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
    var thumbnailData: Data?
}

struct PendingReply: Identifiable {
    let id = UUID()
    let contact: String
    let incomingText: String
    let generatedText: String
    let confidence: Double
    let sendAt: Date          // when the delay expires and message will be sent
    let totalDelay: Double    // total delay in seconds (for progress calculation)
    let chatID: String        // to match/remove when done
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
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let mode = "mei_mode"
        static let confidenceThreshold = "mei_confidenceThreshold"
        static let alwaysRespond = "mei_alwaysRespond"
        static let sendDelayEnabled = "mei_sendDelayEnabled"
        static let sendDelaySeconds = "mei_sendDelaySeconds"
        static let killWord = "mei_killWord"
        static let activeHoursEnabled = "mei_activeHoursEnabled"
        static let activeHoursStart = "mei_activeHoursStart"
        static let activeHoursEnd = "mei_activeHoursEnd"
        static let restrictedTopics = "mei_restrictedTopics"
    }

    var mode: AgentMode = .paused {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }
    var confidenceThreshold: Double = 0.2 {  // TODO: Restore to 0.75 before production
        didSet { UserDefaults.standard.set(confidenceThreshold, forKey: Keys.confidenceThreshold) }
    }
    var alwaysRespond: Bool = false {
        didSet { UserDefaults.standard.set(alwaysRespond, forKey: Keys.alwaysRespond) }
    }
    var sendDelayEnabled: Bool = true {
        didSet { UserDefaults.standard.set(sendDelayEnabled, forKey: Keys.sendDelayEnabled) }
    }
    var sendDelaySeconds: Int = 30 {
        didSet { UserDefaults.standard.set(sendDelaySeconds, forKey: Keys.sendDelaySeconds) }
    }
    var killWord: String = "" {
        didSet { UserDefaults.standard.set(killWord, forKey: Keys.killWord) }
    }
    var activeHoursEnabled: Bool = true {
        didSet { UserDefaults.standard.set(activeHoursEnabled, forKey: Keys.activeHoursEnabled) }
    }
    var activeHoursStart: Int = 8 {   // 8 AM
        didSet { UserDefaults.standard.set(activeHoursStart, forKey: Keys.activeHoursStart) }
    }
    var activeHoursEnd: Int = 23 {    // 11 PM
        didSet { UserDefaults.standard.set(activeHoursEnd, forKey: Keys.activeHoursEnd) }
    }

    var contacts: [ContactConfig] = [] {
        didSet { saveContacts() }
    }
    var recentExchanges: [AgentExchange] = []
    var pendingReplies: [PendingReply] = []

    init() {
        loadSettings()
        loadContacts()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard

        if let modeString = defaults.string(forKey: Keys.mode),
           let savedMode = AgentMode(rawValue: modeString) {
            // Don't restore "killed" mode - start paused instead
            mode = savedMode == .killed ? .paused : savedMode
        }

        if defaults.object(forKey: Keys.confidenceThreshold) != nil {
            confidenceThreshold = defaults.double(forKey: Keys.confidenceThreshold)
        }

        if defaults.object(forKey: Keys.alwaysRespond) != nil {
            alwaysRespond = defaults.bool(forKey: Keys.alwaysRespond)
        }

        if defaults.object(forKey: Keys.sendDelayEnabled) != nil {
            sendDelayEnabled = defaults.bool(forKey: Keys.sendDelayEnabled)
        }

        if defaults.object(forKey: Keys.sendDelaySeconds) != nil {
            sendDelaySeconds = defaults.integer(forKey: Keys.sendDelaySeconds)
        }

        if let savedKillWord = defaults.string(forKey: Keys.killWord) {
            killWord = savedKillWord
        }

        if defaults.object(forKey: Keys.activeHoursEnabled) != nil {
            activeHoursEnabled = defaults.bool(forKey: Keys.activeHoursEnabled)
        }

        if defaults.object(forKey: Keys.activeHoursStart) != nil {
            activeHoursStart = defaults.integer(forKey: Keys.activeHoursStart)
        }

        if defaults.object(forKey: Keys.activeHoursEnd) != nil {
            activeHoursEnd = defaults.integer(forKey: Keys.activeHoursEnd)
        }

        if let savedTopics = defaults.array(forKey: Keys.restrictedTopics) as? [String] {
            restrictedTopics = Set(savedTopics)
        }
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
    ] {
        didSet { UserDefaults.standard.set(Array(restrictedTopics), forKey: Keys.restrictedTopics) }
    }

    var isWithinActiveHours: Bool {
        guard activeHoursEnabled else { return true }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= activeHoursStart && hour < activeHoursEnd
    }

    var shouldProcess: Bool {
        mode == .active || mode == .shadow
    }

    func contactMode(for contactID: String) -> ContactMode {
        contacts.first(where: { $0.contactID == contactID })?.mode ?? .blacklist
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
