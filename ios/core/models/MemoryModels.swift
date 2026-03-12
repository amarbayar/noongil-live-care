import Foundation

// MARK: - Episodic Memory

struct EpisodicMemory: Codable, Identifiable {
    var id: String = UUID().uuidString
    var timestamp: Date
    var summary: String
    var emotion: String?
    var topicsCovered: [String]
    var importance: Double
    var decayRate: Double
    var source: String

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case summary
        case emotion
        case topicsCovered
        case importance
        case decayRate
        case source
    }
}

// MARK: - Semantic Pattern

struct SemanticPattern: Codable, Identifiable {
    var id: String = UUID().uuidString
    var category: String
    var fact: String
    var confidence: Double
    var firstObserved: Date
    var lastConfirmed: Date
    var source: String

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case fact
        case confidence
        case firstObserved
        case lastConfirmed
        case source
    }
}

// MARK: - Procedural Rule

struct ProceduralRule: Codable, Identifiable {
    var id: String = UUID().uuidString
    var trigger: String
    var action: String
    var learnedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case trigger
        case action
        case learnedAt
    }
}

// MARK: - Memory Budget

enum MemoryBudget {
    static let maxEpisodicTokens = 2000
    static let maxSemanticTokens = 1000
    static let maxProceduralTokens = 200
    static let maxProfileTokens = 500
    static let totalBudget = 6000

    static func estimateTokens(_ text: String) -> Int {
        text.count / 4
    }
}

// MARK: - Memory Delta

enum MemoryDeltaOp: String, Codable {
    case add, update, delete, noop
}

struct SemanticUpdate: Codable {
    var id: String?
    var op: MemoryDeltaOp
    var pattern: SemanticPattern
}

struct ProceduralUpdate: Codable {
    var id: String?
    var op: MemoryDeltaOp
    var rule: ProceduralRule
}

struct MemoryDelta: Codable {
    var episodicAdds: [EpisodicMemory]
    var semanticUpdates: [SemanticUpdate]
    var proceduralUpdates: [ProceduralUpdate]
}

extension EpisodicMemory {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        summary = try container.decode(String.self, forKey: .summary)
        emotion = try container.decodeIfPresent(String.self, forKey: .emotion)
        topicsCovered = try container.decodeIfPresent([String].self, forKey: .topicsCovered) ?? []
        importance = try container.decodeIfPresent(Double.self, forKey: .importance) ?? 0.5
        decayRate = try container.decodeIfPresent(Double.self, forKey: .decayRate) ?? 0.2
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "extracted"
    }
}

extension SemanticPattern {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        category = try container.decode(String.self, forKey: .category)
        fact = try container.decode(String.self, forKey: .fact)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5
        firstObserved = try container.decodeIfPresent(Date.self, forKey: .firstObserved) ?? Date()
        lastConfirmed = try container.decodeIfPresent(Date.self, forKey: .lastConfirmed) ?? Date()
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "extracted"
    }
}

extension ProceduralRule {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        trigger = try container.decode(String.self, forKey: .trigger)
        action = try container.decode(String.self, forKey: .action)
        learnedAt = try container.decodeIfPresent(Date.self, forKey: .learnedAt) ?? Date()
    }
}
