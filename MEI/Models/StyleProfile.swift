import Foundation

struct StyleProfile: Codable, Sendable {
    let contact: String
    let phone: String?
    let relationshipTier: String?

    let messageStats: MessageStats?
    let style: StyleDetails?
    let emoji: EmojiDetails?
    let vocabulary: VocabularyDetails?
    let sentiment: SentimentDetails?
    let behavior: BehaviorDetails?
    let topics: TopicDetails?
    let timePatterns: TimePatterns?

    enum CodingKeys: String, CodingKey {
        case contact, phone, style, emoji, vocabulary, sentiment, behavior, topics
        case relationshipTier = "relationship_tier"
        case messageStats = "message_stats"
        case timePatterns = "time_patterns"
    }

    struct MessageStats: Codable, Sendable {
        let totalMessagesFromYou: Int?
        let avgMessageLength: Int?
        let medianMessageLength: Int?
        let maxMessageLength: Int?
        let messagesPerDayAvg: Double?

        enum CodingKeys: String, CodingKey {
            case totalMessagesFromYou = "total_messages_from_you"
            case avgMessageLength = "avg_message_length"
            case medianMessageLength = "median_message_length"
            case maxMessageLength = "max_message_length"
            case messagesPerDayAvg = "messages_per_day_avg"
        }
    }

    struct StyleDetails: Codable, Sendable {
        let capitalization: String?
        let usesPeriods: Bool?
        let usesCommas: String?
        let usesExclamation: String?
        let usesQuestionMarks: Bool?
        let usesEllipsis: Bool?
        let usesApostrophes: Bool?
        let abbreviationLevel: String?
        let avgWordsPerSentence: Double?

        enum CodingKeys: String, CodingKey {
            case capitalization
            case usesPeriods = "uses_periods"
            case usesCommas = "uses_commas"
            case usesExclamation = "uses_exclamation"
            case usesQuestionMarks = "uses_question_marks"
            case usesEllipsis = "uses_ellipsis"
            case usesApostrophes = "uses_apostrophes"
            case abbreviationLevel = "abbreviation_level"
            case avgWordsPerSentence = "avg_words_per_sentence"
        }
    }

    struct EmojiDetails: Codable, Sendable {
        let frequency: Double?
        let topEmojis: [String]?
        let usesEmojiAsResponse: Bool?

        enum CodingKeys: String, CodingKey {
            case frequency
            case topEmojis = "top_emojis"
            case usesEmojiAsResponse = "uses_emoji_as_response"
        }
    }

    struct VocabularyDetails: Codable, Sendable {
        let slangLevel: String?
        let topPhrases: [String]?
        let greetingPatterns: [String]?
        let farewellPatterns: [String]?
        let fillerWords: [String]?
        let vocabularyRichness: Double?

        enum CodingKeys: String, CodingKey {
            case slangLevel = "slang_level"
            case topPhrases = "top_phrases"
            case greetingPatterns = "greeting_patterns"
            case farewellPatterns = "farewell_patterns"
            case fillerWords = "filler_words"
            case vocabularyRichness = "vocabulary_richness"
        }
    }

    struct SentimentDetails: Codable, Sendable {
        let avgCompound: Double?
        let toneLabel: String?
        let positivityRatio: Double?
        let negativityRatio: Double?

        enum CodingKeys: String, CodingKey {
            case avgCompound = "avg_compound"
            case toneLabel = "tone_label"
            case positivityRatio = "positivity_ratio"
            case negativityRatio = "negativity_ratio"
        }
    }

    struct BehaviorDetails: Codable, Sendable {
        let multiMessageTendency: Double?
        let avgMessagesPerBurst: Double?
        let responseTimeMeanMinutes: Double?
        let responseTimeStdMinutes: Double?
        let initiatesConversations: Bool?
        let initiationFrequencyPerWeek: Double?
        let tapbackFrequency: Double?
        let leavesOnReadFrequency: Double?

        enum CodingKeys: String, CodingKey {
            case multiMessageTendency = "multi_message_tendency"
            case avgMessagesPerBurst = "avg_messages_per_burst"
            case responseTimeMeanMinutes = "response_time_mean_minutes"
            case responseTimeStdMinutes = "response_time_std_minutes"
            case initiatesConversations = "initiates_conversations"
            case initiationFrequencyPerWeek = "initiation_frequency_per_week"
            case tapbackFrequency = "tapback_frequency"
            case leavesOnReadFrequency = "leaves_on_read_frequency"
        }
    }

    struct TopicDetails: Codable, Sendable {
        let common: [String]?
        let avoids: [String]?
        let insideReferences: [String]?

        enum CodingKeys: String, CodingKey {
            case common, avoids
            case insideReferences = "inside_references"
        }
    }

    struct TimePatterns: Codable, Sendable {
        let mostActiveHours: [Int]?
        let morningStyle: String?
        let eveningStyle: String?
        let weekendVsWeekday: String?

        enum CodingKeys: String, CodingKey {
            case mostActiveHours = "most_active_hours"
            case morningStyle = "morning_style"
            case eveningStyle = "evening_style"
            case weekendVsWeekday = "weekend_vs_weekday"
        }
    }

    func toPromptSection() -> String {
        var lines: [String] = []
        lines.append("Relationship: \(relationshipTier ?? "unknown")")

        if let stats = messageStats {
            if let avg = stats.avgMessageLength {
                lines.append("Average message length: \(avg) characters")
            }
        }

        if let s = style {
            lines.append("Capitalization: \(s.capitalization ?? "normal")")
            if let p = s.usesPeriods { lines.append("Periods: \(p ? "yes" : "never")") }
            if let c = s.usesCommas { lines.append("Commas: \(c)") }
            if let e = s.usesExclamation { lines.append("Exclamation marks: \(e)") }
            if let q = s.usesQuestionMarks { lines.append("Question marks: \(q ? "yes" : "no")") }
            if let a = s.abbreviationLevel { lines.append("Abbreviation level: \(a)") }
            if let wps = s.avgWordsPerSentence {
                let complexity = wps < 4 ? "very short/fragmented" : wps < 7 ? "short" : wps < 12 ? "medium" : "long"
                lines.append("Sentence complexity: \(complexity) (~\(Int(wps)) words/sentence)")
            }
        }

        if let e = emoji {
            if let freq = e.frequency {
                let label = freq < 0.05 ? "rare" : freq < 0.2 ? "moderate" : "frequent"
                lines.append("Emoji frequency: \(label)")
            }
            if let top = e.topEmojis, !top.isEmpty {
                lines.append("Top emojis: \(top.joined(separator: ", "))")
            }
        }

        if let v = vocabulary {
            if let sl = v.slangLevel { lines.append("Slang level: \(sl)") }
            if let tp = v.topPhrases, !tp.isEmpty {
                lines.append("Common phrases: \"\(tp.joined(separator: "\", \""))\"")
            }
            if let gp = v.greetingPatterns, !gp.isEmpty {
                lines.append("Typical greeting: \"\(gp.first!)\"")
            }
            if let vr = v.vocabularyRichness {
                let label = vr < 0.3 ? "repetitive (uses same words)" : vr < 0.5 ? "moderate" : "varied"
                lines.append("Vocabulary variety: \(label)")
            }
        }

        if let sent = sentiment {
            if let tone = sent.toneLabel {
                lines.append("Overall tone: \(tone)")
            }
        }

        if let b = behavior {
            if let mt = b.multiMessageTendency {
                let pct = Int(mt * 100)
                lines.append("Multi-message tendency: \(pct)%")
            }
            if let rt = b.responseTimeMeanMinutes {
                lines.append("Response time: usually \(Int(rt))-\(Int(rt + (b.responseTimeStdMinutes ?? 2))) minutes")
            }
        }

        return lines.joined(separator: "\n")
    }
}
