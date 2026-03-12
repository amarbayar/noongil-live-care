import XCTest

@MainActor
final class MemoryServiceTests: XCTestCase {

    private var service: MemoryService!

    override func setUp() {
        super.setUp()
        service = MemoryService(storageService: nil, geminiService: nil, userId: "test-user")
    }

    // MARK: - Build Context String

    func testBuildContextString_includesRecentSession() {
        let twoMinAgo = Date().addingTimeInterval(-120)
        service.episodicMemories = [
            EpisodicMemory(
                timestamp: twoMinAgo,
                summary: "Discussed morning tremor improvement",
                emotion: "hopeful",
                topicsCovered: ["symptoms", "medication"],
                importance: 0.9,
                decayRate: 0.0,
                source: "checkin"
            )
        ]

        let context = service.buildContextString()
        XCTAssertTrue(context.contains("tremor improvement"), "Recent session should appear in context")
    }

    func testBuildContextString_includesSemanticPatterns() {
        service.semanticPatterns = [
            SemanticPattern(
                category: "sleep",
                fact: "Usually sleeps 6 hours",
                confidence: 0.8,
                firstObserved: Date(),
                lastConfirmed: Date(),
                source: "extracted"
            )
        ]

        let context = service.buildContextString()
        XCTAssertTrue(context.contains("sleeps 6 hours"))
    }

    func testBuildContextString_includesProceduralRules() {
        service.proceduralRules = [
            ProceduralRule(
                trigger: "user says stop",
                action: "respect immediately, transition to close",
                learnedAt: Date()
            )
        ]

        let context = service.buildContextString()
        XCTAssertTrue(context.contains("user says stop"))
    }

    func testBuildContextString_includesCurrentTime() {
        let context = service.buildContextString()
        XCTAssertTrue(context.contains("[Right Now]"))
        XCTAssertTrue(context.contains("Current local time:"))
    }

    func testBuildContextString_includesCurrentDateAndTimezone() {
        let context = service.buildContextString()
        XCTAssertTrue(context.contains("Today (local device date):"))
        XCTAssertTrue(context.contains("Current timezone:"))
    }

    func testBuildContextString_tokenBudget() {
        // Simulate 30 days of data
        for i in 0..<30 {
            service.episodicMemories.append(EpisodicMemory(
                timestamp: Date().addingTimeInterval(-Double(i) * 86400),
                summary: "Day \(i): Discussed mood, sleep, medication adherence, and symptom progression",
                emotion: "neutral",
                topicsCovered: ["mood", "sleep", "symptoms", "medication"],
                importance: 0.8,
                decayRate: 0.05,
                source: "checkin"
            ))
        }
        for i in 0..<15 {
            service.semanticPatterns.append(SemanticPattern(
                category: "observation",
                fact: "Pattern observation number \(i) about health behavior",
                confidence: 0.7,
                firstObserved: Date(),
                lastConfirmed: Date(),
                source: "extracted"
            ))
        }
        for i in 0..<3 {
            service.proceduralRules.append(ProceduralRule(
                trigger: "trigger \(i)",
                action: "action \(i)",
                learnedAt: Date()
            ))
        }

        let context = service.buildContextString()
        let tokens = MemoryBudget.estimateTokens(context)
        XCTAssertLessThanOrEqual(tokens, MemoryBudget.totalBudget,
            "Context should stay under \(MemoryBudget.totalBudget) tokens, got \(tokens)")
    }

    func testBuildContextString_emptyMemories() {
        let context = service.buildContextString()
        // Should still have [Right Now] section at minimum
        XCTAssertTrue(context.contains("[Right Now]"))
        XCTAssertFalse(context.contains("[Recent Sessions]"))
        XCTAssertFalse(context.contains("[What You Know"))
    }

    // MARK: - Effective Importance

    func testEffectiveImportance_healthFact() {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        let health = EpisodicMemory(
            timestamp: thirtyDaysAgo,
            summary: "Started new medication",
            topicsCovered: ["medication"],
            importance: 1.0,
            decayRate: 0.0,
            source: "checkin"
        )

        let effective = service.effectiveImportance(health, asOf: Date())
        XCTAssertGreaterThan(effective, 0.9, "Health fact (λ=0.0) should retain importance after 30 days")
    }

    func testEffectiveImportance_smallTalk() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)
        let chat = EpisodicMemory(
            timestamp: sevenDaysAgo,
            summary: "Talked about weather",
            topicsCovered: [],
            importance: 0.5,
            decayRate: 0.3,
            source: "casual"
        )

        let effective = service.effectiveImportance(chat, asOf: Date())
        XCTAssertLessThan(effective, 0.05, "Small-talk (λ=0.3) should decay to near-zero after 7 days")
    }

    func testEffectiveImportance_zeroTime() {
        let memory = EpisodicMemory(
            timestamp: Date(),
            summary: "Just happened",
            topicsCovered: [],
            importance: 0.7,
            decayRate: 0.3,
            source: "casual"
        )

        let effective = service.effectiveImportance(memory, asOf: memory.timestamp)
        XCTAssertEqual(effective, 0.7, accuracy: 0.001)
    }

    // MARK: - Consolidate

    func testConsolidate_prunesDecayed() async {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        service.episodicMemories = [
            EpisodicMemory(
                timestamp: thirtyDaysAgo,
                summary: "Health fact stays",
                topicsCovered: ["medication"],
                importance: 1.0,
                decayRate: 0.0,
                source: "checkin"
            ),
            EpisodicMemory(
                timestamp: thirtyDaysAgo,
                summary: "Small talk decays",
                topicsCovered: [],
                importance: 0.3,
                decayRate: 0.3,
                source: "casual"
            )
        ]

        await service.consolidateMemories()

        XCTAssertEqual(service.episodicMemories.count, 1)
        XCTAssertEqual(service.episodicMemories[0].summary, "Health fact stays")
    }

    func testConsolidate_mergesDuplicateSemantics() async {
        let now = Date()
        service.semanticPatterns = [
            SemanticPattern(
                category: "sleep",
                fact: "Usually sleeps 6 hours",
                confidence: 0.6,
                firstObserved: now.addingTimeInterval(-86400),
                lastConfirmed: now.addingTimeInterval(-86400),
                source: "extracted"
            ),
            SemanticPattern(
                category: "sleep",
                fact: "Usually sleeps 6 hours",
                confidence: 0.6,
                firstObserved: now,
                lastConfirmed: now,
                source: "extracted"
            )
        ]

        await service.consolidateMemories()

        XCTAssertEqual(service.semanticPatterns.count, 1, "Duplicates should merge")
        XCTAssertGreaterThan(service.semanticPatterns[0].confidence, 0.6, "Confidence should increase on merge")
    }

    func testConsolidate_capsEpisodicCount() async {
        for i in 0..<60 {
            service.episodicMemories.append(EpisodicMemory(
                timestamp: Date().addingTimeInterval(-Double(i) * 3600),
                summary: "Memory \(i)",
                topicsCovered: ["mood"],
                importance: 0.8,
                decayRate: 0.0,
                source: "checkin"
            ))
        }

        await service.consolidateMemories()

        XCTAssertLessThanOrEqual(service.episodicMemories.count, 50)
    }

    // MARK: - Apply Delta

    func testApplyDelta_addEpisodic() async {
        let delta = MemoryDelta(
            episodicAdds: [
                EpisodicMemory(
                    timestamp: Date(),
                    summary: "New session about mood",
                    topicsCovered: ["mood"],
                    importance: 0.8,
                    decayRate: 0.1,
                    source: "checkin"
                )
            ],
            semanticUpdates: [],
            proceduralUpdates: []
        )

        await service.applyDelta(delta)

        XCTAssertEqual(service.episodicMemories.count, 1)
        XCTAssertEqual(service.episodicMemories[0].summary, "New session about mood")
    }

    func testApplyDelta_updateSemantic() async {
        let existingId = "pattern-1"
        service.semanticPatterns = [
            SemanticPattern(
                id: existingId,
                category: "sleep",
                fact: "Sleeps 5 hours",
                confidence: 0.5,
                firstObserved: Date().addingTimeInterval(-86400),
                lastConfirmed: Date().addingTimeInterval(-86400),
                source: "extracted"
            )
        ]

        let delta = MemoryDelta(
            episodicAdds: [],
            semanticUpdates: [
                SemanticUpdate(
                    id: existingId,
                    op: .update,
                    pattern: SemanticPattern(
                        category: "sleep",
                        fact: "Sleeps 6 hours now",
                        confidence: 0.8,
                        firstObserved: Date(),
                        lastConfirmed: Date(),
                        source: "extracted"
                    )
                )
            ],
            proceduralUpdates: []
        )

        await service.applyDelta(delta)

        XCTAssertEqual(service.semanticPatterns.count, 1)
        XCTAssertEqual(service.semanticPatterns[0].fact, "Sleeps 6 hours now")
        XCTAssertEqual(service.semanticPatterns[0].confidence, 0.8)
    }

    func testApplyDelta_deleteSemantic() async {
        let existingId = "pattern-to-delete"
        service.semanticPatterns = [
            SemanticPattern(
                id: existingId,
                category: "preference",
                fact: "Outdated fact",
                confidence: 0.3,
                firstObserved: Date(),
                lastConfirmed: Date(),
                source: "extracted"
            )
        ]

        let delta = MemoryDelta(
            episodicAdds: [],
            semanticUpdates: [
                SemanticUpdate(
                    id: existingId,
                    op: .delete,
                    pattern: SemanticPattern(
                        category: "",
                        fact: "",
                        confidence: 0,
                        firstObserved: Date(),
                        lastConfirmed: Date(),
                        source: ""
                    )
                )
            ],
            proceduralUpdates: []
        )

        await service.applyDelta(delta)

        XCTAssertEqual(service.semanticPatterns.count, 0, "Pattern should be deleted")
    }

    func testApplyDelta_addProcedural() async {
        let delta = MemoryDelta(
            episodicAdds: [],
            semanticUpdates: [],
            proceduralUpdates: [
                ProceduralUpdate(
                    id: nil,
                    op: .add,
                    rule: ProceduralRule(
                        trigger: "user says enough",
                        action: "stop asking questions immediately",
                        learnedAt: Date()
                    )
                )
            ]
        )

        await service.applyDelta(delta)

        XCTAssertEqual(service.proceduralRules.count, 1)
        XCTAssertEqual(service.proceduralRules[0].trigger, "user says enough")
    }

    func testApplyDelta_noopIsIgnored() async {
        let delta = MemoryDelta(
            episodicAdds: [],
            semanticUpdates: [
                SemanticUpdate(id: nil, op: .noop, pattern: SemanticPattern(
                    category: "", fact: "", confidence: 0,
                    firstObserved: Date(), lastConfirmed: Date(), source: ""
                ))
            ],
            proceduralUpdates: []
        )

        await service.applyDelta(delta)

        XCTAssertEqual(service.semanticPatterns.count, 0, "noop should not add patterns")
    }

    // MARK: - Recent Detail Supplement

    func testExtractMemories_withoutGemini_capturesRecentFoodDetail() async {
        let delta = await service.extractMemories(transcript: [
            (role: "user", text: "I'm eating salsa right now.")
        ])

        XCTAssertNotNil(delta)
        XCTAssertTrue(delta?.episodicAdds.contains(where: {
            $0.summary.contains("eating salsa") && $0.source == "recent_detail"
        }) == true)
    }

    func testExtractMemories_mergesLLMAndRecentCreationDetail() async {
        let mockGemini = MockMemoryGeminiService()
        mockGemini.structuredResponseToReturn = [
            "episodicAdds": [
                [
                    "summary": "Talked about a calm afternoon.",
                    "emotion": "calm",
                    "topicsCovered": ["casual"],
                    "importance": 0.4,
                    "decayRate": 0.2,
                    "source": "casual"
                ]
            ],
            "semanticUpdates": [],
            "proceduralUpdates": []
        ]
        service = MemoryService(storageService: nil, geminiService: mockGemini, userId: "test-user")

        let delta = await service.extractMemories(transcript: [
            (role: "user", text: "I just generated a song about the rain.")
        ])

        XCTAssertEqual(delta?.episodicAdds.count, 2)
        XCTAssertTrue(delta?.episodicAdds.contains(where: {
            $0.summary.contains("generated a song about the rain") && $0.source == "recent_detail"
        }) == true)
    }

    func testBuildContextString_includesRecentDetailMemory() {
        service.episodicMemories = [
            EpisodicMemory(
                timestamp: Date().addingTimeInterval(-60),
                summary: "They mentioned they were eating salsa.",
                emotion: nil,
                topicsCovered: ["food", "recent_detail"],
                importance: 0.65,
                decayRate: 0.12,
                source: "recent_detail"
            )
        ]

        let context = service.buildContextString()

        XCTAssertTrue(context.contains("eating salsa"))
    }

    // MARK: - Deterministic Recall

    func testRecallResponse_returnsRecentFoodDetailForRecallQuestion() {
        service.episodicMemories = [
            EpisodicMemory(
                timestamp: Date().addingTimeInterval(-45),
                summary: "They mentioned they were eating salsa and chips.",
                emotion: nil,
                topicsCovered: ["food", "recent_detail"],
                importance: 0.65,
                decayRate: 0.12,
                source: "recent_detail"
            )
        ]

        let response = service.recallResponse(for: "What was I just eating?")

        XCTAssertEqual(response, "Earlier you mentioned you were eating salsa and chips.")
    }

    func testRecallResponse_returnsRecentCreationDetailForRecallQuestion() {
        service.episodicMemories = [
            EpisodicMemory(
                timestamp: Date().addingTimeInterval(-90),
                summary: "They said they generated a song about the rain.",
                emotion: nil,
                topicsCovered: ["creation", "recent_detail"],
                importance: 0.75,
                decayRate: 0.1,
                source: "recent_detail"
            )
        ]

        let response = service.recallResponse(for: "Do you remember what I generated earlier?")

        XCTAssertEqual(response, "Earlier you mentioned you generated a song about the rain.")
    }
}

private final class MockMemoryGeminiService: GeminiService {
    var structuredResponseToReturn: [String: Any] = [:]

    override func sendStructuredRequest(
        text: String,
        systemInstruction: String,
        jsonSchema: [String: Any]
    ) async throws -> [String: Any] {
        structuredResponseToReturn
    }
}
