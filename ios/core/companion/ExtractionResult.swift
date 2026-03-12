import Foundation

/// Structured health data extracted from conversation by the LLM.
/// All fields optional — the LLM only fills in what was actually discussed.
struct ExtractionResult: Codable {
    var moodLabel: String?           // "positive", "negative", "neutral"
    var moodDetail: String?          // user's exact words about mood
    var moodScore: Int?              // 1-5

    var sleepHours: Double?
    var sleepQuality: String?        // "good", "bad", "okay"
    var sleepInterruptions: Int?

    var symptoms: [ExtractedSymptom]?
    var medicationsMentioned: [ExtractedMedication]?

    var topicsCovered: [String]?
    var topicsNotYetCovered: [String]?  // drives follow-up questions
    var newVocabulary: ExtractedVocabulary?
    var corrections: [ExtractedCorrection]?
    var userSentiment: String?

    // Triggers, activities, concerns — flow to backend graph, not into CheckIn model
    var triggers: [ExtractedTrigger]?
    var activities: [ExtractedActivity]?
    var concerns: [ExtractedConcern]?

    // Conversation guidance — drives companion behavior
    var emotion: String?              // "calm", "anxious", "frustrated", "happy", "sad", "tired", "in_pain"
    var engagementLevel: String?      // "low", "medium", "high"
    var recommendedAction: String?    // "reflect", "affirm", "ask", "summarize", "close"

    // User agency — LLM detects the user's desire to end/change the conversation
    var userWantsToEnd: Bool?         // true if user signals they want to wrap up, stop, move on
    var detectedIntent: String?       // "checkin", "casual", "creative"
    var creativeCanvasAction: String? // "show", "close", "cancel", "status"
    var creativeRequestedMediaType: String? // "image", "video", "music", "animation"
}

struct ExtractedSymptom: Codable {
    var type: String                 // maps to SymptomType raw value
    var severity: String?            // "mild", "moderate", "severe", "pretty bad"
    var location: String?
    var duration: String?
    var userWords: String?           // user's exact description
    var comparedToYesterday: String? // "better", "same", "worse"
}

struct ExtractedMedication: Codable {
    var name: String
    var status: String?              // "taken", "missed", "skipped", "delayed"
    var userWords: String?           // "I took my morning pill"
}

struct ExtractedVocabulary: Codable {
    var symptomWords: [String: String]?        // "shaky" → "tremor"
    var moodWords: [String: String]?           // "blah" → "negative"
    var painWords: [String: String]?           // "aching" → "pain"
    var medicationNicknames: [String: String]? // "blue pill" → medication name
}

struct ExtractedCorrection: Codable {
    var field: String                // what was wrong
    var originalValue: String?       // what we had
    var correctedValue: String       // what the user said instead
}

struct ExtractedTrigger: Codable {
    var name: String                 // "daughter's visit", "plumber noise"
    var type: String?                // "stress", "environmental", "social", "dietary"
    var userWords: String?
}

struct ExtractedActivity: Codable {
    var name: String                 // "walking", "physical therapy"
    var duration: String?            // "30 minutes"
    var intensity: String?           // "light", "moderate", "vigorous"
    var userWords: String?
}

struct ExtractedConcern: Codable {
    var text: String                 // "worried about falling"
    var theme: String?               // "mobility", "medication", "social", "cognitive"
    var urgency: String?             // "low", "medium", "high"
}

// MARK: - Normalization

extension ExtractionResult {

    /// Normalizes severity strings to 1-5 scale.
    static func normalizeSeverity(_ severity: String?) -> Int? {
        guard let s = severity?.lowercased() else { return nil }
        switch s {
        case "none", "no": return 0
        case "very mild", "barely", "a little", "slight": return 1
        case "mild", "minor", "a bit": return 2
        case "moderate", "some", "noticeable": return 3
        case "severe", "bad", "a lot", "pretty bad", "significant": return 4
        case "very severe", "terrible", "extreme", "awful", "worst": return 5
        default:
            if let num = Int(s), (1...5).contains(num) { return num }
            return 3 // default to moderate if unrecognized
        }
    }

    /// Normalizes sleep quality strings to 1-5 scale.
    static func normalizeSleepQuality(_ quality: String?) -> Int? {
        guard let q = quality?.lowercased() else { return nil }
        switch q {
        case "terrible", "awful", "very bad": return 1
        case "bad", "poor", "not great": return 2
        case "okay", "so-so", "alright", "fair": return 3
        case "good", "well", "fine", "decent": return 4
        case "great", "excellent", "amazing", "wonderful": return 5
        default: return nil
        }
    }

    /// Applies extracted data to a CheckIn, merging without overwriting existing values.
    func applyToCheckIn(_ checkIn: inout CheckIn) {
        // Mood
        if checkIn.mood == nil && (moodLabel != nil || moodDetail != nil || moodScore != nil) {
            checkIn.mood = MoodEntry(
                score: moodScore,
                description: moodDetail,
                label: moodLabel
            )
        }

        // Sleep
        if checkIn.sleep == nil && (sleepHours != nil || sleepQuality != nil) {
            checkIn.sleep = SleepEntry(
                hours: sleepHours,
                quality: ExtractionResult.normalizeSleepQuality(sleepQuality),
                interruptions: sleepInterruptions,
                description: sleepQuality
            )
        }

        // Symptoms (append new ones)
        if let extracted = symptoms {
            for symptom in extracted {
                let type = SymptomType(rawValue: symptom.type) ?? .other
                let alreadyTracked = checkIn.symptoms.contains { $0.type == type }
                if !alreadyTracked {
                    checkIn.symptoms.append(SymptomEntry(
                        type: type,
                        severity: ExtractionResult.normalizeSeverity(symptom.severity),
                        location: symptom.location,
                        duration: symptom.duration,
                        userDescription: symptom.userWords,
                        comparedToYesterday: symptom.comparedToYesterday
                    ))
                }
            }
        }

        // Medication adherence (append new mentions)
        if let extracted = medicationsMentioned {
            for med in extracted {
                let alreadyTracked = checkIn.medicationAdherence.contains {
                    $0.medicationName.lowercased() == med.name.lowercased()
                }
                if !alreadyTracked {
                    let status = MedicationStatus(rawValue: med.status ?? "taken") ?? .taken
                    checkIn.medicationAdherence.append(MedicationAdherenceEntry(
                        medicationName: med.name,
                        status: status,
                        reportedVia: "voice"
                    ))
                }
            }
        }
    }

    /// OpenAPI-subset JSON schema for Gemini structured output.
    /// Gemini's responseSchema uses a subset of OpenAPI 3.0 — no $ref, no allOf, etc.
    static var geminiSchema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "moodLabel": ["type": "STRING", "enum": ["positive", "negative", "neutral"]],
                "moodDetail": ["type": "STRING"],
                "moodScore": ["type": "INTEGER"],
                "sleepHours": ["type": "NUMBER"],
                "sleepQuality": ["type": "STRING"],
                "sleepInterruptions": ["type": "INTEGER"],
                "symptoms": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "type": ["type": "STRING"],
                            "severity": ["type": "STRING"],
                            "location": ["type": "STRING"],
                            "duration": ["type": "STRING"],
                            "userWords": ["type": "STRING"],
                            "comparedToYesterday": ["type": "STRING", "enum": ["better", "same", "worse"]]
                        ] as [String: Any],
                        "required": ["type"]
                    ] as [String: Any]
                ] as [String: Any],
                "medicationsMentioned": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "name": ["type": "STRING"],
                            "status": ["type": "STRING", "enum": ["taken", "missed", "skipped", "delayed"]],
                            "userWords": ["type": "STRING"]
                        ] as [String: Any],
                        "required": ["name"]
                    ] as [String: Any]
                ] as [String: Any],
                "triggers": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "name": ["type": "STRING"],
                            "type": ["type": "STRING", "enum": ["stress", "environmental", "social", "dietary"]],
                            "userWords": ["type": "STRING"]
                        ] as [String: Any],
                        "required": ["name"]
                    ] as [String: Any]
                ] as [String: Any],
                "activities": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "name": ["type": "STRING"],
                            "duration": ["type": "STRING"],
                            "intensity": ["type": "STRING", "enum": ["light", "moderate", "vigorous"]],
                            "userWords": ["type": "STRING"]
                        ] as [String: Any],
                        "required": ["name"]
                    ] as [String: Any]
                ] as [String: Any],
                "concerns": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "text": ["type": "STRING"],
                            "theme": ["type": "STRING", "enum": ["mobility", "medication", "social", "cognitive"]],
                            "urgency": ["type": "STRING", "enum": ["low", "medium", "high"]]
                        ] as [String: Any],
                        "required": ["text"]
                    ] as [String: Any]
                ] as [String: Any],
                "topicsCovered": ["type": "ARRAY", "items": ["type": "STRING"]],
                "topicsNotYetCovered": ["type": "ARRAY", "items": ["type": "STRING"]],
                "newVocabulary": [
                    "type": "OBJECT",
                    "properties": [
                        "symptomWords": ["type": "OBJECT"],
                        "moodWords": ["type": "OBJECT"],
                        "painWords": ["type": "OBJECT"],
                        "medicationNicknames": ["type": "OBJECT"]
                    ] as [String: Any]
                ] as [String: Any],
                "corrections": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "field": ["type": "STRING"],
                            "originalValue": ["type": "STRING"],
                            "correctedValue": ["type": "STRING"]
                        ] as [String: Any],
                        "required": ["field", "correctedValue"]
                    ] as [String: Any]
                ] as [String: Any],
                "userSentiment": ["type": "STRING"],
                "emotion": ["type": "STRING", "enum": ["calm", "anxious", "frustrated", "happy", "sad", "tired", "in_pain"]],
                "engagementLevel": ["type": "STRING", "enum": ["low", "medium", "high"]],
                "recommendedAction": ["type": "STRING", "enum": ["reflect", "affirm", "ask", "summarize", "close"]],
                "userWantsToEnd": ["type": "BOOLEAN"],
                "detectedIntent": ["type": "STRING", "enum": ["checkin", "casual", "creative"]],
                "creativeCanvasAction": ["type": "STRING", "enum": ["show", "close", "cancel", "status"]],
                "creativeRequestedMediaType": ["type": "STRING", "enum": ["image", "video", "music", "animation"]]
            ] as [String: Any],
            "required": ["emotion", "engagementLevel", "recommendedAction", "userWantsToEnd"]
        ]
    }

    /// Builds a VocabularyMap from extracted vocabulary for merging.
    func buildVocabularyUpdate() -> VocabularyMap? {
        guard let vocab = newVocabulary else { return nil }
        var map = VocabularyMap()
        map.symptomWords = vocab.symptomWords ?? [:]
        map.moodWords = vocab.moodWords ?? [:]
        map.painWords = vocab.painWords ?? [:]
        map.medicationNicknames = vocab.medicationNicknames ?? [:]
        return map
    }
}
