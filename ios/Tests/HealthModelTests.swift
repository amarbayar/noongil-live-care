import XCTest

final class HealthModelTests: XCTestCase {

    // MARK: - CheckIn

    func testCheckInInitializesWithDefaults() {
        let checkIn = CheckIn(userId: "user-1", type: .morning)

        XCTAssertEqual(checkIn.userId, "user-1")
        XCTAssertEqual(checkIn.type, .morning)
        XCTAssertEqual(checkIn.completionStatus, .inProgress)
        XCTAssertEqual(checkIn.inputMethod, "voice")
        XCTAssertNil(checkIn.mood)
        XCTAssertNil(checkIn.sleep)
        XCTAssertTrue(checkIn.symptoms.isEmpty)
        XCTAssertTrue(checkIn.medicationAdherence.isEmpty)
        XCTAssertNil(checkIn.aiSummary)
        XCTAssertNil(checkIn.completedAt)
        XCTAssertNil(checkIn.durationSeconds)
    }

    func testCheckInTypesEncode() throws {
        let encoder = JSONEncoder()
        let morning = try encoder.encode(CheckInType.morning)
        let evening = try encoder.encode(CheckInType.evening)
        let adhoc = try encoder.encode(CheckInType.adhoc)

        XCTAssertEqual(String(data: morning, encoding: .utf8), "\"morning\"")
        XCTAssertEqual(String(data: evening, encoding: .utf8), "\"evening\"")
        XCTAssertEqual(String(data: adhoc, encoding: .utf8), "\"adhoc\"")
    }

    // MARK: - VocabularyMap

    func testVocabularyMapMergeDoesNotOverwrite() {
        var map = VocabularyMap()
        map.symptomWords["shaky"] = "tremor"
        map.moodWords["meh"] = "neutral"

        var newVocab = VocabularyMap()
        newVocab.symptomWords["shaky"] = "rigidity"  // should NOT overwrite
        newVocab.symptomWords["achy"] = "pain"        // should add
        newVocab.moodWords["great"] = "positive"      // should add

        map.merge(new: newVocab)

        XCTAssertEqual(map.symptomWords["shaky"], "tremor")  // first word wins
        XCTAssertEqual(map.symptomWords["achy"], "pain")
        XCTAssertEqual(map.moodWords["meh"], "neutral")
        XCTAssertEqual(map.moodWords["great"], "positive")
    }

    func testVocabularyMapReverseLookup() {
        var map = VocabularyMap()
        map.symptomWords["shaky"] = "tremor"
        map.symptomWords["stiff"] = "rigidity"

        XCTAssertEqual(map.userWord(for: .tremor), "shaky")
        XCTAssertEqual(map.userWord(for: .rigidity), "stiff")
        XCTAssertNil(map.userWord(for: .pain))
    }

    func testVocabularyMapEncodesDecodes() throws {
        var map = VocabularyMap()
        map.symptomWords["shaky"] = "tremor"
        map.moodWords["blah"] = "negative"
        map.medicationNicknames["morning pill"] = "med-123"

        let encoder = JSONEncoder()
        let data = try encoder.encode(map)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VocabularyMap.self, from: data)

        XCTAssertEqual(decoded.symptomWords["shaky"], "tremor")
        XCTAssertEqual(decoded.moodWords["blah"], "negative")
        XCTAssertEqual(decoded.medicationNicknames["morning pill"], "med-123")
    }

    // MARK: - ExtractionResult

    func testExtractionResultDecodesFullJSON() throws {
        let json = """
        {
            "moodLabel": "positive",
            "moodDetail": "feeling pretty good today",
            "moodScore": 4,
            "sleepHours": 7.5,
            "sleepQuality": "good",
            "symptoms": [
                {
                    "type": "tremor",
                    "severity": "mild",
                    "userWords": "a little shaky this morning"
                }
            ],
            "topicsCovered": ["mood", "sleep", "symptoms"],
            "topicsNotYetCovered": ["medication"],
            "userSentiment": "generally upbeat"
        }
        """

        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(ExtractionResult.self, from: data)

        XCTAssertEqual(result.moodLabel, "positive")
        XCTAssertEqual(result.moodDetail, "feeling pretty good today")
        XCTAssertEqual(result.moodScore, 4)
        XCTAssertEqual(result.sleepHours, 7.5)
        XCTAssertEqual(result.sleepQuality, "good")
        XCTAssertEqual(result.symptoms?.count, 1)
        XCTAssertEqual(result.symptoms?.first?.type, "tremor")
        XCTAssertEqual(result.symptoms?.first?.severity, "mild")
        XCTAssertEqual(result.topicsCovered, ["mood", "sleep", "symptoms"])
        XCTAssertEqual(result.topicsNotYetCovered, ["medication"])
    }

    func testExtractionResultDecodesPartialJSON() throws {
        let json = """
        {
            "moodLabel": "negative",
            "moodDetail": "not great"
        }
        """

        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(ExtractionResult.self, from: data)

        XCTAssertEqual(result.moodLabel, "negative")
        XCTAssertEqual(result.moodDetail, "not great")
        XCTAssertNil(result.moodScore)
        XCTAssertNil(result.sleepHours)
        XCTAssertNil(result.symptoms)
        XCTAssertNil(result.medicationsMentioned)
        XCTAssertNil(result.topicsCovered)
    }

    func testExtractionResultDecodesEmptyJSON() throws {
        let json = "{}"
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(ExtractionResult.self, from: data)

        XCTAssertNil(result.moodLabel)
        XCTAssertNil(result.sleepHours)
        XCTAssertNil(result.symptoms)
    }

    func testExtractionResultDecodesConversationGuidance() throws {
        let json = """
        {
            "moodLabel": "negative",
            "moodDetail": "my hands were really shaky",
            "emotion": "frustrated",
            "engagementLevel": "high",
            "recommendedAction": "reflect"
        }
        """

        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(ExtractionResult.self, from: data)

        XCTAssertEqual(result.emotion, "frustrated")
        XCTAssertEqual(result.engagementLevel, "high")
        XCTAssertEqual(result.recommendedAction, "reflect")
    }

    func testExtractionResultGuidanceFieldsNilWhenAbsent() throws {
        let json = """
        {
            "moodLabel": "positive",
            "moodDetail": "feeling good"
        }
        """

        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(ExtractionResult.self, from: data)

        XCTAssertNil(result.emotion)
        XCTAssertNil(result.engagementLevel)
        XCTAssertNil(result.recommendedAction)
    }

    // MARK: - Severity Normalization

    func testSeverityNormalization() {
        XCTAssertEqual(ExtractionResult.normalizeSeverity("mild"), 2)
        XCTAssertEqual(ExtractionResult.normalizeSeverity("a little"), 1)
        XCTAssertEqual(ExtractionResult.normalizeSeverity("moderate"), 3)
        XCTAssertEqual(ExtractionResult.normalizeSeverity("severe"), 4)
        XCTAssertEqual(ExtractionResult.normalizeSeverity("terrible"), 5)
        XCTAssertEqual(ExtractionResult.normalizeSeverity("pretty bad"), 4)
        XCTAssertEqual(ExtractionResult.normalizeSeverity(nil), nil)
        XCTAssertEqual(ExtractionResult.normalizeSeverity("3"), 3)
    }

    func testSleepQualityNormalization() {
        XCTAssertEqual(ExtractionResult.normalizeSleepQuality("terrible"), 1)
        XCTAssertEqual(ExtractionResult.normalizeSleepQuality("bad"), 2)
        XCTAssertEqual(ExtractionResult.normalizeSleepQuality("okay"), 3)
        XCTAssertEqual(ExtractionResult.normalizeSleepQuality("good"), 4)
        XCTAssertEqual(ExtractionResult.normalizeSleepQuality("great"), 5)
        XCTAssertEqual(ExtractionResult.normalizeSleepQuality(nil), nil)
    }

    // MARK: - Apply Extraction to CheckIn

    func testApplyExtractionToCheckIn() {
        var checkIn = CheckIn(userId: "user-1", type: .morning)

        let result = ExtractionResult(
            moodLabel: "positive",
            moodDetail: "feeling good",
            moodScore: 4,
            sleepHours: 8.0,
            sleepQuality: "good",
            symptoms: [
                ExtractedSymptom(type: "tremor", severity: "mild", userWords: "a bit shaky")
            ],
            medicationsMentioned: [
                ExtractedMedication(name: "Levodopa", status: "taken")
            ]
        )

        result.applyToCheckIn(&checkIn)

        XCTAssertEqual(checkIn.mood?.label, "positive")
        XCTAssertEqual(checkIn.mood?.description, "feeling good")
        XCTAssertEqual(checkIn.mood?.score, 4)
        XCTAssertEqual(checkIn.sleep?.hours, 8.0)
        XCTAssertEqual(checkIn.symptoms.count, 1)
        XCTAssertEqual(checkIn.symptoms.first?.type, .tremor)
        XCTAssertEqual(checkIn.medicationAdherence.count, 1)
        XCTAssertEqual(checkIn.medicationAdherence.first?.medicationName, "Levodopa")
        XCTAssertEqual(checkIn.medicationAdherence.first?.status, .taken)
    }

    func testApplyExtractionDoesNotOverwriteExisting() {
        var checkIn = CheckIn(userId: "user-1", type: .morning)
        checkIn.mood = MoodEntry(score: 3, description: "so-so", label: "neutral")

        let result = ExtractionResult(
            moodLabel: "positive",
            moodDetail: "actually great",
            moodScore: 5
        )

        result.applyToCheckIn(&checkIn)

        // Mood should NOT be overwritten — first extraction wins
        XCTAssertEqual(checkIn.mood?.label, "neutral")
        XCTAssertEqual(checkIn.mood?.score, 3)
    }

    func testApplyExtractionDoesNotDuplicateSymptoms() {
        var checkIn = CheckIn(userId: "user-1", type: .morning)
        checkIn.symptoms = [
            SymptomEntry(type: .tremor, severity: 2, userDescription: "shaky")
        ]

        let result = ExtractionResult(
            symptoms: [
                ExtractedSymptom(type: "tremor", severity: "moderate"), // same type
                ExtractedSymptom(type: "fatigue", severity: "mild")    // new type
            ]
        )

        result.applyToCheckIn(&checkIn)

        XCTAssertEqual(checkIn.symptoms.count, 2) // tremor not duplicated
        XCTAssertTrue(checkIn.symptoms.contains { $0.type == .tremor })
        XCTAssertTrue(checkIn.symptoms.contains { $0.type == .fatigue })
    }

    // MARK: - Vocabulary from Extraction

    func testBuildVocabularyUpdate() {
        let result = ExtractionResult(
            newVocabulary: ExtractedVocabulary(
                symptomWords: ["shaky": "tremor"],
                moodWords: ["meh": "neutral"],
                painWords: nil,
                medicationNicknames: ["morning pill": "Levodopa"]
            )
        )

        let vocab = result.buildVocabularyUpdate()
        XCTAssertNotNil(vocab)
        XCTAssertEqual(vocab?.symptomWords["shaky"], "tremor")
        XCTAssertEqual(vocab?.moodWords["meh"], "neutral")
        XCTAssertEqual(vocab?.medicationNicknames["morning pill"], "Levodopa")
    }

    // MARK: - Transcript

    func testTranscriptAddEntry() {
        var transcript = Transcript(checkInId: "checkin-1")

        XCTAssertEqual(transcript.entryCount, 0)
        XCTAssertTrue(transcript.entries.isEmpty)

        transcript.addEntry(role: .assistant, text: "Good morning!")
        transcript.addEntry(role: .user, text: "Hi there")

        XCTAssertEqual(transcript.entryCount, 2)
        XCTAssertEqual(transcript.entries[0].role, .assistant)
        XCTAssertEqual(transcript.entries[0].text, "Good morning!")
        XCTAssertEqual(transcript.entries[1].role, .user)
        XCTAssertEqual(transcript.entries[1].text, "Hi there")
    }

    // MARK: - Medication

    func testMedicationInitializesWithDefaults() {
        let med = Medication(userId: "user-1", name: "Levodopa", dosage: "100mg")

        XCTAssertEqual(med.name, "Levodopa")
        XCTAssertEqual(med.dosage, "100mg")
        XCTAssertTrue(med.isActive)
        XCTAssertFalse(med.reminderEnabled)
        XCTAssertTrue(med.schedule.isEmpty)
    }

    // MARK: - UserProfile

    func testUserProfileInitializesWithDefaults() {
        let profile = UserProfile()

        XCTAssertEqual(profile.companionName, "Mira")
        XCTAssertEqual(profile.language, "en")
        XCTAssertFalse(profile.onboardingCompleted)
        XCTAssertEqual(profile.weekNumber, 0)
        XCTAssertNotNil(profile.timezone)
        XCTAssertEqual(profile.speechAccommodationLevel, .none)
        XCTAssertNil(profile.baselineASRConfidence)
    }

    // MARK: - SpeechAccommodationLevel

    func testSpeechAccommodationLevelEncodesDecodes() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for level in SpeechAccommodationLevel.allCases {
            let data = try encoder.encode(level)
            let decoded = try decoder.decode(SpeechAccommodationLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }

    func testSpeechAccommodationLevelRawValues() {
        XCTAssertEqual(SpeechAccommodationLevel.none.rawValue, "none")
        XCTAssertEqual(SpeechAccommodationLevel.mild.rawValue, "mild")
        XCTAssertEqual(SpeechAccommodationLevel.moderate.rawValue, "moderate")
        XCTAssertEqual(SpeechAccommodationLevel.severe.rawValue, "severe")
    }

    // MARK: - SpeechAccommodationConfig

    func testAccommodationConfigNone() {
        let config = SpeechAccommodationConfig.config(for: .none)

        XCTAssertEqual(config.minSilenceDuration, 0.25, accuracy: 0.01)
        XCTAssertEqual(config.vadThreshold, 0.5, accuracy: 0.01)
        XCTAssertEqual(config.minSpeechDuration, 0.5, accuracy: 0.01)
        XCTAssertEqual(config.maxSpeechDuration, 30.0, accuracy: 0.01)
        XCTAssertEqual(config.confidenceThreshold, 0.6, accuracy: 0.01)
    }

    func testAccommodationConfigMild() {
        let config = SpeechAccommodationConfig.config(for: .mild)

        XCTAssertEqual(config.minSilenceDuration, 1.5, accuracy: 0.01)
        XCTAssertEqual(config.vadThreshold, 0.45, accuracy: 0.01)
        XCTAssertEqual(config.confidenceThreshold, 0.4, accuracy: 0.01)
    }

    func testAccommodationConfigModerate() {
        let config = SpeechAccommodationConfig.config(for: .moderate)

        XCTAssertEqual(config.minSilenceDuration, 2.5, accuracy: 0.01)
        XCTAssertEqual(config.vadThreshold, 0.35, accuracy: 0.01)
        XCTAssertEqual(config.confidenceThreshold, 0.3, accuracy: 0.01)
    }

    func testAccommodationConfigSevere() {
        let config = SpeechAccommodationConfig.config(for: .severe)

        XCTAssertEqual(config.minSilenceDuration, 4.0, accuracy: 0.01)
        XCTAssertEqual(config.vadThreshold, 0.25, accuracy: 0.01)
        XCTAssertEqual(config.maxSpeechDuration, 60.0, accuracy: 0.01)
        XCTAssertEqual(config.confidenceThreshold, 0.2, accuracy: 0.01)
    }

    func testAccommodationConfigSevereHasLongerSpeechDuration() {
        let none = SpeechAccommodationConfig.config(for: .none)
        let severe = SpeechAccommodationConfig.config(for: .severe)

        XCTAssertGreaterThan(severe.minSilenceDuration, none.minSilenceDuration)
        XCTAssertGreaterThan(severe.maxSpeechDuration, none.maxSpeechDuration)
        XCTAssertLessThan(severe.vadThreshold, none.vadThreshold)
        XCTAssertLessThan(severe.confidenceThreshold, none.confidenceThreshold)
    }
}
