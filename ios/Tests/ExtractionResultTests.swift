import XCTest

final class ExtractionResultTests: XCTestCase {

    // MARK: - Decode with Triggers, Activities, Concerns

    func testDecodeWithTriggersActivitiesConcerns() throws {
        let json = """
        {
            "moodLabel": "negative",
            "moodDetail": "stressed out",
            "moodScore": 2,
            "triggers": [
                {
                    "name": "plumber noise",
                    "type": "environmental",
                    "userWords": "the plumber was banging pipes all morning"
                }
            ],
            "activities": [
                {
                    "name": "walking",
                    "duration": "30 minutes",
                    "intensity": "light",
                    "userWords": "went for a short walk"
                }
            ],
            "concerns": [
                {
                    "text": "worried about falling",
                    "theme": "mobility",
                    "urgency": "high"
                }
            ],
            "emotion": "anxious",
            "engagementLevel": "high",
            "recommendedAction": "reflect"
        }
        """

        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(ExtractionResult.self, from: data)

        XCTAssertEqual(result.moodLabel, "negative")
        XCTAssertEqual(result.moodScore, 2)

        XCTAssertEqual(result.triggers?.count, 1)
        XCTAssertEqual(result.triggers?.first?.name, "plumber noise")
        XCTAssertEqual(result.triggers?.first?.type, "environmental")
        XCTAssertEqual(result.triggers?.first?.userWords, "the plumber was banging pipes all morning")

        XCTAssertEqual(result.activities?.count, 1)
        XCTAssertEqual(result.activities?.first?.name, "walking")
        XCTAssertEqual(result.activities?.first?.duration, "30 minutes")
        XCTAssertEqual(result.activities?.first?.intensity, "light")

        XCTAssertEqual(result.concerns?.count, 1)
        XCTAssertEqual(result.concerns?.first?.text, "worried about falling")
        XCTAssertEqual(result.concerns?.first?.theme, "mobility")
        XCTAssertEqual(result.concerns?.first?.urgency, "high")

        // Round-trip: encode then decode
        let encoded = try JSONEncoder().encode(result)
        let roundTrip = try JSONDecoder().decode(ExtractionResult.self, from: encoded)

        XCTAssertEqual(roundTrip.triggers?.first?.name, "plumber noise")
        XCTAssertEqual(roundTrip.activities?.first?.name, "walking")
        XCTAssertEqual(roundTrip.concerns?.first?.text, "worried about falling")
        XCTAssertEqual(roundTrip.emotion, "anxious")
        XCTAssertEqual(roundTrip.engagementLevel, "high")
        XCTAssertEqual(roundTrip.recommendedAction, "reflect")
    }

    // MARK: - Backward Compatibility

    func testDecodeWithoutNewFieldsStillWorks() throws {
        let json = """
        {
            "moodLabel": "positive",
            "moodDetail": "feeling good",
            "moodScore": 4,
            "sleepHours": 7.5,
            "sleepQuality": "good",
            "symptoms": [
                {
                    "type": "tremor",
                    "severity": "mild"
                }
            ],
            "topicsCovered": ["mood", "sleep"],
            "topicsNotYetCovered": ["medication"]
        }
        """

        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(ExtractionResult.self, from: data)

        XCTAssertEqual(result.moodLabel, "positive")
        XCTAssertEqual(result.moodScore, 4)
        XCTAssertEqual(result.sleepHours, 7.5)
        XCTAssertEqual(result.symptoms?.count, 1)

        XCTAssertNil(result.triggers)
        XCTAssertNil(result.activities)
        XCTAssertNil(result.concerns)
    }

    // MARK: - Gemini Schema Validation

    func testGeminiSchemaContainsRequiredFields() {
        let schema = ExtractionResult.geminiSchema
        guard let required = schema["required"] as? [String] else {
            XCTFail("geminiSchema missing 'required' array")
            return
        }

        XCTAssertTrue(required.contains("emotion"))
        XCTAssertTrue(required.contains("engagementLevel"))
        XCTAssertTrue(required.contains("recommendedAction"))
    }

    func testGeminiSchemaContainsNewFieldTypes() {
        let schema = ExtractionResult.geminiSchema
        guard let properties = schema["properties"] as? [String: Any] else {
            XCTFail("geminiSchema missing 'properties' dictionary")
            return
        }

        XCTAssertNotNil(properties["triggers"], "triggers missing from schema properties")
        XCTAssertNotNil(properties["activities"], "activities missing from schema properties")
        XCTAssertNotNil(properties["concerns"], "concerns missing from schema properties")

        // Verify they are ARRAY types
        if let triggers = properties["triggers"] as? [String: Any] {
            XCTAssertEqual(triggers["type"] as? String, "ARRAY")
        } else {
            XCTFail("triggers should be a dictionary with type ARRAY")
        }

        if let activities = properties["activities"] as? [String: Any] {
            XCTAssertEqual(activities["type"] as? String, "ARRAY")
        } else {
            XCTFail("activities should be a dictionary with type ARRAY")
        }

        if let concerns = properties["concerns"] as? [String: Any] {
            XCTAssertEqual(concerns["type"] as? String, "ARRAY")
        } else {
            XCTFail("concerns should be a dictionary with type ARRAY")
        }

        if let creativeCanvasAction = properties["creativeCanvasAction"] as? [String: Any] {
            XCTAssertEqual(creativeCanvasAction["type"] as? String, "STRING")
        } else {
            XCTFail("creativeCanvasAction missing from schema properties")
        }

        if let creativeRequestedMediaType = properties["creativeRequestedMediaType"] as? [String: Any] {
            XCTAssertEqual(creativeRequestedMediaType["type"] as? String, "STRING")
        } else {
            XCTFail("creativeRequestedMediaType missing from schema properties")
        }
    }
}
