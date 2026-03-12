import XCTest

final class MemoryModelsTests: XCTestCase {

    // MARK: - Episodic Memory Decay

    func testEpisodicMemoryDecay_healthFactRetains() {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        let health = EpisodicMemory(
            timestamp: thirtyDaysAgo,
            summary: "Started new medication dosage",
            topicsCovered: ["medication"],
            importance: 1.0,
            decayRate: 0.0,
            source: "checkin"
        )

        let effective = effectiveImportance(health, asOf: Date())
        XCTAssertEqual(effective, 1.0, accuracy: 0.01, "Health fact (λ=0.0) should retain full importance")
    }

    func testEpisodicMemoryDecay_smallTalkDecays() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)
        let chat = EpisodicMemory(
            timestamp: sevenDaysAgo,
            summary: "Talked about the weather",
            topicsCovered: [],
            importance: 0.5,
            decayRate: 0.3,
            source: "casual"
        )

        let effective = effectiveImportance(chat, asOf: Date())
        XCTAssertLessThan(effective, 0.1, "Small-talk (λ=0.3) should decay significantly after 7 days")
    }

    func testEpisodicMemoryDecay_recentSmallTalkRetains() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let chat = EpisodicMemory(
            timestamp: oneHourAgo,
            summary: "Told a joke about cats",
            topicsCovered: [],
            importance: 0.5,
            decayRate: 0.3,
            source: "casual"
        )

        let effective = effectiveImportance(chat, asOf: Date())
        XCTAssertGreaterThan(effective, 0.4, "Recent small-talk should retain most importance")
    }

    // MARK: - Token Estimation

    func testMemoryBudgetTokenEstimation() {
        let text = String(repeating: "word ", count: 100) // ~500 chars
        let estimated = MemoryBudget.estimateTokens(text)
        XCTAssertEqual(estimated, text.count / 4)
        XCTAssertGreaterThan(estimated, 100)
        XCTAssertLessThan(estimated, 200)
    }

    func testMemoryBudgetTotalBudget() {
        let total = MemoryBudget.maxEpisodicTokens
            + MemoryBudget.maxSemanticTokens
            + MemoryBudget.maxProceduralTokens
            + MemoryBudget.maxProfileTokens
        XCTAssertLessThanOrEqual(total, MemoryBudget.totalBudget)
    }

    // MARK: - Codable Round-Trip

    func testMemoryDeltaCodable() throws {
        let now = Date()
        let delta = MemoryDelta(
            episodicAdds: [
                EpisodicMemory(
                    timestamp: now,
                    summary: "Test session",
                    topicsCovered: ["mood"],
                    importance: 0.8,
                    decayRate: 0.1,
                    source: "checkin"
                )
            ],
            semanticUpdates: [
                SemanticUpdate(
                    id: nil,
                    op: .add,
                    pattern: SemanticPattern(
                        category: "sleep",
                        fact: "Usually sleeps 6 hours",
                        confidence: 0.7,
                        firstObserved: now,
                        lastConfirmed: now,
                        source: "extracted"
                    )
                )
            ],
            proceduralUpdates: [
                ProceduralUpdate(
                    id: nil,
                    op: .add,
                    rule: ProceduralRule(
                        trigger: "user says stop",
                        action: "respect immediately",
                        learnedAt: now
                    )
                )
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(delta)
        let decoded = try JSONDecoder().decode(MemoryDelta.self, from: data)

        XCTAssertEqual(decoded.episodicAdds.count, 1)
        XCTAssertEqual(decoded.episodicAdds[0].summary, "Test session")
        XCTAssertEqual(decoded.semanticUpdates.count, 1)
        XCTAssertEqual(decoded.semanticUpdates[0].op, .add)
        XCTAssertEqual(decoded.proceduralUpdates.count, 1)
        XCTAssertEqual(decoded.proceduralUpdates[0].rule.trigger, "user says stop")
    }

    func testMemoryDeltaDecodesLLMStylePayloadWithoutDates() throws {
        let json = """
        {
          "episodicAdds": [
            {
              "summary": "They mentioned they were eating salsa.",
              "topicsCovered": ["food", "recent_detail"],
              "importance": 0.65,
              "decayRate": 0.12,
              "source": "recent_detail"
            }
          ],
          "semanticUpdates": [
            {
              "op": "add",
              "pattern": {
                "category": "preference",
                "fact": "Likes spicy food",
                "confidence": 0.8,
                "source": "extracted"
              }
            }
          ],
          "proceduralUpdates": [
            {
              "op": "add",
              "rule": {
                "trigger": "user asks for recall",
                "action": "answer from memory context"
              }
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MemoryDelta.self, from: data)

        XCTAssertEqual(decoded.episodicAdds.count, 1)
        XCTAssertFalse(decoded.episodicAdds[0].id.isEmpty)
        XCTAssertEqual(decoded.semanticUpdates.count, 1)
        XCTAssertFalse(decoded.semanticUpdates[0].pattern.id.isEmpty)
        XCTAssertEqual(decoded.proceduralUpdates.count, 1)
        XCTAssertFalse(decoded.proceduralUpdates[0].rule.id.isEmpty)
    }

    func testEpisodicMemoryCodable() throws {
        let memory = EpisodicMemory(
            timestamp: Date(),
            summary: "Discussed tremor improvement",
            emotion: "hopeful",
            topicsCovered: ["symptoms", "medication"],
            importance: 0.9,
            decayRate: 0.0,
            source: "checkin"
        )

        let data = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(EpisodicMemory.self, from: data)

        XCTAssertEqual(decoded.summary, memory.summary)
        XCTAssertEqual(decoded.emotion, "hopeful")
        XCTAssertEqual(decoded.topicsCovered, ["symptoms", "medication"])
        XCTAssertEqual(decoded.importance, 0.9)
        XCTAssertEqual(decoded.decayRate, 0.0)
    }

    func testSemanticPatternCodable() throws {
        let pattern = SemanticPattern(
            category: "preference",
            fact: "Prefers tea before bed",
            confidence: 0.8,
            firstObserved: Date(),
            lastConfirmed: Date(),
            source: "stated"
        )

        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(SemanticPattern.self, from: data)

        XCTAssertEqual(decoded.fact, pattern.fact)
        XCTAssertEqual(decoded.confidence, 0.8)
    }

    // MARK: - Helpers

    private func effectiveImportance(_ memory: EpisodicMemory, asOf date: Date) -> Double {
        let daysSince = date.timeIntervalSince(memory.timestamp) / 86400
        return memory.importance * exp(-memory.decayRate * daysSince)
    }
}
