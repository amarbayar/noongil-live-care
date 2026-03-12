import Foundation

/// Maps user's natural words to structured types. Mira always mirrors the user's own language.
/// Stored at /users/{userId}/profile/vocabulary in Firestore.
struct VocabularyMap: Codable {
    var symptomWords: [String: String]          // "shaky" → "tremor"
    var moodWords: [String: String]             // "meh" → "neutral"
    var painWords: [String: String]             // "hurting" → "pain"
    var medicationNicknames: [String: String]   // "morning pill" → medicationId
    var updatedAt: Date

    init() {
        self.symptomWords = [:]
        self.moodWords = [:]
        self.painWords = [:]
        self.medicationNicknames = [:]
        self.updatedAt = Date()
    }

    /// Merges new vocabulary. First word wins — existing mappings are never overwritten.
    mutating func merge(new: VocabularyMap) {
        for (word, type) in new.symptomWords where symptomWords[word] == nil {
            symptomWords[word] = type
        }
        for (word, label) in new.moodWords where moodWords[word] == nil {
            moodWords[word] = label
        }
        for (word, type) in new.painWords where painWords[word] == nil {
            painWords[word] = type
        }
        for (word, medId) in new.medicationNicknames where medicationNicknames[word] == nil {
            medicationNicknames[word] = medId
        }
        self.updatedAt = Date()
    }

    /// Reverse lookup: given a symptom type, find the user's preferred word.
    func userWord(for symptomType: SymptomType) -> String? {
        let typeString = symptomType.rawValue
        return symptomWords.first(where: { $0.value == typeString })?.key
    }
}
