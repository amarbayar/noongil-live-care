import XCTest

/// Integration tests for Gemini Live multi-turn conversations with function calling.
/// Uses AUDIO response mode (native audio model requires it) + outputTranscription for verification.
///
/// These tests connect to the real Gemini Live WebSocket API.
/// Excluded from `./build.sh test` (unit tests). Run with:
///   ./build.sh test-live
///
/// Or run the Python version (no sandbox issues):
///   python3 Tests/test-gemini-live.py
final class GeminiLiveIntegrationTests: XCTestCase {

    private var service: GeminiLiveService!

    override func setUp() async throws {
        try super.setUpWithError()
        service = GeminiLiveService()
        // Native audio model requires AUDIO output — we verify via outputTranscription
        service.useNativeAudio = true
    }

    override func tearDown() {
        service?.disconnect()
        service = nil
        super.tearDown()
    }

    // MARK: - Test 1: Basic text→audio round-trip

    func testCanConnectAndReceiveTextResponse() async throws {
        let connected = expectation(description: "Connected")
        let gotResponse = expectation(description: "Got response")

        var transcript = ""

        service.onConnectionStateChanged = { state in
            if state == .ready { connected.fulfill() }
        }

        service.onOutputTranscript = { text in
            transcript += text
        }

        service.onTurnComplete = {
            if !transcript.isEmpty {
                gotResponse.fulfill()
            }
        }

        service.connect()
        await fulfillment(of: [connected], timeout: 15)

        service.sendText("Say exactly one word: PONG")
        await fulfillment(of: [gotResponse], timeout: 30)

        XCTAssertFalse(transcript.isEmpty, "Should receive transcribed response")
        print("[TEST-1] Transcript: \(transcript)")
    }

    // MARK: - Test 2: Function calling triggers on first turn

    func testCheckInToolsGetCalledBeforeResponse() async throws {
        service.systemInstruction = """
        You are a health companion conducting a check-in.
        CRITICAL RULE: You MUST call get_check_in_guidance BEFORE every single response.
        Never respond without first calling get_check_in_guidance.
        """
        service.extraFunctionDeclarations = LiveCheckInManager.checkInToolDeclarations

        let connected = expectation(description: "Connected")
        let gotToolCall = expectation(description: "Got tool call")

        var firstToolCallName = ""

        service.onConnectionStateChanged = { state in
            if state == .ready { connected.fulfill() }
        }

        service.onToolCall = { [weak self] id, name, args in
            if firstToolCallName.isEmpty {
                firstToolCallName = name
                gotToolCall.fulfill()
            }
            self?.service.sendToolResponse(id: id, response: [
                "topicsCovered": [] as [String],
                "topicsRemaining": ["mood", "sleep", "symptoms", "medication"],
                "activeMedications": ["Levodopa 100mg"],
                "emotion": "calm",
                "engagementLevel": "medium",
                "recommendedAction": "ask",
                "nextTopicHint": "mood",
                "instruction": "Greet warmly and ask about their mood."
            ])
        }

        service.connect()
        await fulfillment(of: [connected], timeout: 15)

        service.sendText("Hi, I'm ready for my check-in")
        await fulfillment(of: [gotToolCall], timeout: 30)

        XCTAssertEqual(firstToolCallName, "get_check_in_guidance",
                       "First tool call should be get_check_in_guidance, got: \(firstToolCallName)")
    }

    // MARK: - Test 3: Multi-turn check-in conversation

    func testFullCheckInConversationFlow() async throws {
        service.systemInstruction = """
        You are Mira, a warm wellness companion helping with a daily check-in.

        RULES (follow strictly):
        1. ALWAYS call get_check_in_guidance BEFORE every response to the user.
        2. Read the guidance carefully. Use topicsRemaining and instruction to decide what to ask.
        3. When recommendedAction is "close", say a brief warm goodbye and call complete_check_in.
        4. Keep responses to 1-2 short sentences.
        5. Be warm but concise.
        """
        service.extraFunctionDeclarations = LiveCheckInManager.checkInToolDeclarations

        var toolCalls: [(id: String, name: String)] = []
        var modelTranscripts: [String] = []
        var currentTranscript = ""
        var turnNumber = 0

        let userMessages = [
            "Hi Mira, I'm ready for my check-in",
            "I'm feeling pretty good today, calm and positive",
            "I slept about 7 hours, woke up once but went back to sleep easily",
            "My tremor was really mild today, no stiffness at all",
            "Yes I took my Levodopa this morning on schedule",
            "Thanks Mira!"
        ]
        var nextUserMessageIndex = 0

        let connected = expectation(description: "Connected")
        let checkInCompleted = expectation(description: "Check-in completed")
        checkInCompleted.assertForOverFulfill = false

        func guidanceForTurn(_ turn: Int) -> [String: Any] {
            let progressions: [([String], [String], String, String, String)] = [
                ([], ["mood", "sleep", "symptoms", "medication"], "ask", "mood",
                 "Greet warmly and ask about mood."),
                (["mood"], ["sleep", "symptoms", "medication"], "affirm", "sleep",
                 "Affirm positive mood, ask about sleep."),
                (["mood", "sleep"], ["symptoms", "medication"], "ask", "symptoms",
                 "Good sleep. Ask about symptoms."),
                (["mood", "sleep", "symptoms"], ["medication"], "affirm", "medication",
                 "Mild symptoms. Ask about medication."),
                (["mood", "sleep", "symptoms", "medication"], [], "close", "",
                 "All topics covered. Wrap up warmly and call complete_check_in."),
            ]
            let idx = min(turn, progressions.count - 1)
            let (covered, remaining, action, hint, instruction) = progressions[idx]
            return [
                "topicsCovered": covered,
                "topicsRemaining": remaining,
                "activeMedications": ["Levodopa 100mg 3x/day"],
                "emotion": "calm",
                "engagementLevel": "medium",
                "recommendedAction": action,
                "nextTopicHint": hint,
                "instruction": instruction
            ]
        }

        service.onConnectionStateChanged = { state in
            if state == .ready { connected.fulfill() }
        }

        service.onToolCall = { [weak self] id, name, args in
            guard let self = self else { return }
            toolCalls.append((id: id, name: name))
            print("[TEST-3] Turn \(turnNumber) | Tool: \(name)")

            if name == "get_check_in_guidance" {
                self.service.sendToolResponse(id: id, response: guidanceForTurn(turnNumber))
            } else if name == "complete_check_in" {
                self.service.sendToolResponse(id: id, response: ["success": true, "durationSeconds": 45])
                checkInCompleted.fulfill()
            }
        }

        service.onOutputTranscript = { text in
            currentTranscript += text
        }

        service.onTurnComplete = { [weak self] in
            guard let self = self else { return }
            if !currentTranscript.isEmpty {
                modelTranscripts.append(currentTranscript)
                print("[TEST-3] Turn \(turnNumber) | Mira: \(currentTranscript.prefix(150))")
                currentTranscript = ""
            }
            turnNumber += 1
            nextUserMessageIndex += 1
            if nextUserMessageIndex < userMessages.count && turnNumber < 10 {
                let msg = userMessages[nextUserMessageIndex]
                print("[TEST-3] Turn \(turnNumber) | User: \(msg)")
                self.service.sendText(msg)
            }
        }

        service.connect()
        await fulfillment(of: [connected], timeout: 15)

        print("[TEST-3] Turn 0 | User: \(userMessages[0])")
        service.sendText(userMessages[0])

        await fulfillment(of: [checkInCompleted], timeout: 180)

        let guidanceCalls = toolCalls.filter { $0.name == "get_check_in_guidance" }
        let completeCalls = toolCalls.filter { $0.name == "complete_check_in" }

        print("\n[TEST-3] ========= SUMMARY =========")
        print("[TEST-3] Guidance calls: \(guidanceCalls.count)")
        print("[TEST-3] Complete calls: \(completeCalls.count)")
        print("[TEST-3] Responses: \(modelTranscripts.count)")
        print("[TEST-3] ==============================\n")

        XCTAssertGreaterThanOrEqual(guidanceCalls.count, 3,
            "Gemini should call get_check_in_guidance at least 3 times")
        XCTAssertEqual(completeCalls.count, 1,
            "Gemini should call complete_check_in exactly once")
        XCTAssertGreaterThanOrEqual(modelTranscripts.count, 3,
            "Should have at least 3 model responses")
        if let first = toolCalls.first {
            XCTAssertEqual(first.name, "get_check_in_guidance", "First tool call should be guidance")
        }
        if let last = toolCalls.last {
            XCTAssertEqual(last.name, "complete_check_in", "Last tool call should be complete")
        }
    }

    // MARK: - Test 4: Model responds after tool response

    func testModelRespondsAfterGuidanceToolResponse() async throws {
        service.systemInstruction = """
        You are a health companion. ALWAYS call get_check_in_guidance before responding.
        After receiving guidance, respond based on the instruction. One sentence max.
        """
        service.extraFunctionDeclarations = LiveCheckInManager.checkInToolDeclarations

        let connected = expectation(description: "Connected")
        let gotModelResponse = expectation(description: "Got model response after tool")

        var receivedToolCall = false
        var transcriptAfterTool = ""

        service.onConnectionStateChanged = { state in
            if state == .ready { connected.fulfill() }
        }

        service.onToolCall = { [weak self] id, name, args in
            receivedToolCall = true
            self?.service.sendToolResponse(id: id, response: [
                "topicsCovered": [] as [String],
                "topicsRemaining": ["mood"],
                "activeMedications": [] as [String],
                "emotion": "calm",
                "engagementLevel": "medium",
                "recommendedAction": "ask",
                "nextTopicHint": "mood",
                "instruction": "Ask how they are feeling today."
            ])
        }

        service.onOutputTranscript = { text in
            if receivedToolCall { transcriptAfterTool += text }
        }

        service.onTurnComplete = {
            if !transcriptAfterTool.isEmpty {
                gotModelResponse.fulfill()
            }
        }

        service.connect()
        await fulfillment(of: [connected], timeout: 15)

        service.sendText("Hello")
        await fulfillment(of: [gotModelResponse], timeout: 30)

        XCTAssertTrue(receivedToolCall, "Should have received a tool call")
        XCTAssertFalse(transcriptAfterTool.isEmpty, "Model should respond after tool response")
    }
}
