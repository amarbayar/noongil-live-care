import XCTest

@MainActor
final class MemoryBenchmarkTests: XCTestCase {

    // MARK: - Token Budget

    func testTokenBudget_30DaysOfCheckIns() {
        let service = MemoryService(storageService: nil, geminiService: nil, userId: "bench")

        // Add 30 episodic memories (1 per day)
        for i in 0..<30 {
            service.episodicMemories.append(EpisodicMemory(
                timestamp: Date().addingTimeInterval(-Double(i) * 86400),
                summary: "Day \(30 - i): Discussed mood improvement, slept 7 hours, took medication on time, mild tremor in the morning",
                emotion: ["hopeful", "calm", "tired", "neutral"][i % 4],
                topicsCovered: ["mood", "sleep", "symptoms", "medication"],
                importance: 0.8,
                decayRate: 0.05,
                source: "checkin"
            ))
        }

        // Add 15 semantic patterns
        let categories = ["sleep", "mood", "medication", "preference", "routine"]
        for i in 0..<15 {
            service.semanticPatterns.append(SemanticPattern(
                category: categories[i % categories.count],
                fact: "Semantic pattern \(i): detailed observation about the person's health behavior and preferences",
                confidence: 0.5 + Double(i) * 0.03,
                firstObserved: Date().addingTimeInterval(-Double(i) * 86400 * 2),
                lastConfirmed: Date().addingTimeInterval(-Double(i) * 86400),
                source: "extracted"
            ))
        }

        // Add 3 procedural rules
        service.proceduralRules = [
            ProceduralRule(trigger: "user says stop", action: "respect immediately, transition to close", learnedAt: Date()),
            ProceduralRule(trigger: "user mentions daughter", action: "ask warmly, this is important to them", learnedAt: Date()),
            ProceduralRule(trigger: "morning check-in", action: "ask about sleep first, they care most about rest", learnedAt: Date())
        ]

        let context = service.buildContextString()
        let tokens = MemoryBudget.estimateTokens(context)

        XCTAssertLessThanOrEqual(tokens, MemoryBudget.totalBudget,
            "30-day context should fit in budget: got \(tokens) tokens (limit: \(MemoryBudget.totalBudget))")
    }

    // MARK: - Continuity

    func testContinuity_recentSessionInContext() {
        let service = MemoryService(storageService: nil, geminiService: nil, userId: "bench")

        let recent = EpisodicMemory(
            timestamp: Date().addingTimeInterval(-120), // 2 min ago
            summary: "Discussed morning tremor improvement after starting new dosage",
            emotion: "hopeful",
            topicsCovered: ["symptoms", "medication"],
            importance: 0.9,
            decayRate: 0.0,
            source: "checkin"
        )
        service.episodicMemories = [recent]

        let context = service.buildContextString()
        XCTAssertTrue(context.contains("tremor improvement"),
            "Very recent session should appear in context verbatim")
    }

    func testContinuity_semanticFactInContext() {
        let service = MemoryService(storageService: nil, geminiService: nil, userId: "bench")

        service.semanticPatterns = [
            SemanticPattern(
                category: "sleep",
                fact: "Usually sleeps 6 hours, wakes at 3am",
                confidence: 0.9,
                firstObserved: Date().addingTimeInterval(-7 * 86400),
                lastConfirmed: Date(),
                source: "extracted"
            )
        ]

        let context = service.buildContextString()
        XCTAssertTrue(context.contains("sleeps 6 hours"))
    }

    // MARK: - Decay

    func testDecay_healthVsSmallTalk() {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        let service = MemoryService(storageService: nil, geminiService: nil, userId: "bench")

        let health = EpisodicMemory(
            timestamp: thirtyDaysAgo,
            summary: "Started new medication regimen",
            topicsCovered: ["medication"],
            importance: 1.0,
            decayRate: 0.0,
            source: "checkin"
        )
        let chat = EpisodicMemory(
            timestamp: thirtyDaysAgo,
            summary: "Talked about weather and sports",
            topicsCovered: [],
            importance: 0.5,
            decayRate: 0.3,
            source: "casual"
        )

        XCTAssertGreaterThan(service.effectiveImportance(health, asOf: Date()), 0.9,
            "Health facts should persist indefinitely")
        XCTAssertLessThan(service.effectiveImportance(chat, asOf: Date()), 0.05,
            "Small-talk should fade after 30 days")
    }

    func testDecay_personalSharing_moderateDecay() {
        let fourteenDaysAgo = Date().addingTimeInterval(-14 * 86400)
        let service = MemoryService(storageService: nil, geminiService: nil, userId: "bench")

        let personal = EpisodicMemory(
            timestamp: fourteenDaysAgo,
            summary: "Daughter visited, felt happy",
            topicsCovered: ["social"],
            importance: 0.7,
            decayRate: 0.1,
            source: "checkin"
        )

        let effective = service.effectiveImportance(personal, asOf: Date())
        // exp(-0.1 * 14) ≈ 0.247, so 0.7 * 0.247 ≈ 0.173
        XCTAssertGreaterThan(effective, 0.1, "Personal sharing should partially persist at 14 days")
        XCTAssertLessThan(effective, 0.5, "Personal sharing should decay somewhat at 14 days")
    }

    // MARK: - Intent Detection Accuracy (fast-path only)

    func testFastPathIntentDetection_batch() {
        let service = UnifiedGuidanceService(geminiService: GeminiService(), memoryService: nil)

        // These test only the fast-path keyword detection.
        // Cases that require LLM (e.g., "I've been feeling down" → checkin) are excluded —
        // those are handled by the extraction's `detectedIntent` field.
        let cases: [(String, ConversationIntent?)] = [
            ("draw me a sunset", .creative),
            ("make an image of a cat", .creative),
            ("let's check in", .checkin),
            ("wellness check please", .checkin),
            ("sketch a mountain landscape", .creative),
            ("tell me a joke", nil),         // ambiguous → LLM decides
            ("what's the weather?", nil),    // ambiguous → LLM decides
            ("I've been feeling down", nil), // health signal → LLM decides
        ]

        var correct = 0
        for (text, expected) in cases {
            let detected = service.detectFastPathIntent(text)
            if detected == expected { correct += 1 }
        }

        let accuracy = Double(correct) / Double(cases.count)
        XCTAssertGreaterThanOrEqual(accuracy, 0.75,
            "Fast-path intent detection should be >= 75% accurate, got \(Int(accuracy * 100))%")
    }

    // MARK: - Graceful Exit

    func testGracefulExit_fastPathSignals() {
        let service = UnifiedGuidanceService(geminiService: GeminiService(), memoryService: nil)

        // These are the unambiguous signals caught by fast-path
        let fastPathSignals = [
            "wrap up", "let's stop", "I'm done", "that's all",
            "let's finish", "no more questions", "that's enough",
            "all done", "we're done"
        ]

        for signal in fastPathSignals {
            XCTAssertTrue(service.detectFastPathAgencySignal(signal),
                "Fast-path should catch: '\(signal)'")
        }
    }

    func testGracefulExit_indirectSignals_notCaughtByFastPath() {
        let service = UnifiedGuidanceService(geminiService: GeminiService(), memoryService: nil)

        // These require LLM extraction (userWantsToEnd = true)
        let indirectSignals = [
            "I think we're good",
            "nothing else comes to mind",
            "I need to go now",
            "that covers everything",
            "I'm all set",
            "let's call it a day"
        ]

        for signal in indirectSignals {
            XCTAssertFalse(service.detectFastPathAgencySignal(signal),
                "Indirect signal should rely on LLM, not fast-path: '\(signal)'")
        }
    }

    func testGracefulExit_normalSpeechNotTriggered() {
        let normalPhrases = [
            "I slept pretty well",
            "My medication is helping",
            "Good morning",
            "I walked for 30 minutes today"
        ]
        let service = UnifiedGuidanceService(geminiService: GeminiService(), memoryService: nil)

        for phrase in normalPhrases {
            XCTAssertFalse(service.detectFastPathAgencySignal(phrase),
                "Normal speech should not trigger exit: '\(phrase)'")
        }
    }

    // MARK: - Consolidation Performance

    func testConsolidate_withLargeDataset() async {
        let service = MemoryService(storageService: nil, geminiService: nil, userId: "bench")

        // 100 memories, mix of decayed and fresh
        for i in 0..<100 {
            service.episodicMemories.append(EpisodicMemory(
                timestamp: Date().addingTimeInterval(-Double(i) * 86400),
                summary: "Memory \(i)",
                topicsCovered: ["mood"],
                importance: i < 50 ? 0.8 : 0.3,
                decayRate: i < 50 ? 0.0 : 0.3,
                source: "checkin"
            ))
        }

        // 20 semantic patterns with duplicates
        for i in 0..<20 {
            service.semanticPatterns.append(SemanticPattern(
                category: "sleep",
                fact: i < 10 ? "Sleeps 6 hours" : "Unique fact \(i)",
                confidence: 0.5,
                firstObserved: Date(),
                lastConfirmed: Date(),
                source: "extracted"
            ))
        }

        await service.consolidateMemories()

        // Episodic should be capped at 50
        XCTAssertLessThanOrEqual(service.episodicMemories.count, 50)
        // Duplicate semantics should be merged
        XCTAssertLessThan(service.semanticPatterns.count, 20)
    }

    // MARK: - Feature Flag

    func testFeatureFlag_unifiedGuidanceEnabled() {
        let flags = FeatureFlagService()
        flags.applyFlags(["unified_guidance_enabled": true])
        XCTAssertTrue(flags.unifiedGuidanceEnabled)

        flags.applyFlags(["unified_guidance_enabled": false])
        XCTAssertFalse(flags.unifiedGuidanceEnabled)
    }
}
