import Foundation

/// Computes health trends from recent check-in data for display.
/// Pure computation — no storage dependency. Feed it check-ins, get trends back.
struct HealthHistoryService {

    // MARK: - Mood Trend

    struct MoodPoint {
        let date: Date
        let score: Int       // 1-5
        let label: String?
        let description: String?
    }

    /// Extracts mood data points from check-ins, most recent first.
    /// Falls back to label-based scoring when numeric score is nil.
    static func moodTrend(from checkIns: [CheckIn]) -> [MoodPoint] {
        checkIns.compactMap { checkIn in
            guard let mood = checkIn.mood else { return nil }
            let score = mood.score ?? scoreFallback(from: mood.label)
            guard let resolvedScore = score else { return nil }
            return MoodPoint(
                date: checkIn.startedAt,
                score: resolvedScore,
                label: mood.label,
                description: mood.description
            )
        }
    }

    /// Average mood score over the given check-ins.
    /// Falls back to label-based scoring when numeric score is nil.
    static func averageMood(from checkIns: [CheckIn]) -> Double? {
        let scores = checkIns.compactMap { checkIn -> Int? in
            guard let mood = checkIn.mood else { return nil }
            return mood.score ?? scoreFallback(from: mood.label)
        }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    /// Maps mood labels to approximate numeric scores.
    private static func scoreFallback(from label: String?) -> Int? {
        switch label?.lowercased() {
        case "positive": return 4
        case "neutral": return 3
        case "negative": return 2
        default: return nil
        }
    }

    // MARK: - Sleep Trend

    struct SleepPoint {
        let date: Date
        let hours: Double
        let quality: Int?    // 1-5
        let interruptions: Int?
    }

    /// Extracts sleep data points from check-ins, most recent first.
    static func sleepTrend(from checkIns: [CheckIn]) -> [SleepPoint] {
        checkIns.compactMap { checkIn in
            guard let sleep = checkIn.sleep, let hours = sleep.hours else { return nil }
            return SleepPoint(
                date: checkIn.startedAt,
                hours: hours,
                quality: sleep.quality,
                interruptions: sleep.interruptions
            )
        }
    }

    /// Average sleep hours over the given check-ins.
    static func averageSleep(from checkIns: [CheckIn]) -> Double? {
        let hours = checkIns.compactMap { $0.sleep?.hours }
        guard !hours.isEmpty else { return nil }
        return hours.reduce(0, +) / Double(hours.count)
    }

    // MARK: - Symptom Summary

    struct SymptomSummary {
        let type: SymptomType
        let occurrences: Int
        let averageSeverity: Double?
        let latestDescription: String?
    }

    /// Summarizes symptom frequency and severity across check-ins.
    static func symptomSummary(from checkIns: [CheckIn]) -> [SymptomSummary] {
        var occurrences: [SymptomType: Int] = [:]
        var severities: [SymptomType: [Int]] = [:]
        var latestDescriptions: [SymptomType: String] = [:]

        for checkIn in checkIns {
            for symptom in checkIn.symptoms {
                occurrences[symptom.type, default: 0] += 1
                if let severity = symptom.severity {
                    severities[symptom.type, default: []].append(severity)
                }
                if let desc = symptom.userDescription, latestDescriptions[symptom.type] == nil {
                    latestDescriptions[symptom.type] = desc
                }
            }
        }

        return occurrences.keys.sorted { occurrences[$0]! > occurrences[$1]! }.map { type in
            let sev = severities[type]
            let avgSev = sev.flatMap { arr in
                arr.isEmpty ? nil : Double(arr.reduce(0, +)) / Double(arr.count)
            }
            return SymptomSummary(
                type: type,
                occurrences: occurrences[type]!,
                averageSeverity: avgSev,
                latestDescription: latestDescriptions[type]
            )
        }
    }

    // MARK: - Daily Summary

    struct DailySummary {
        let date: Date
        let moodScore: Int?
        let moodLabel: String?
        let moodDescription: String?
        let sleepHours: Double?
        let symptomCount: Int
        let symptomNames: [String]
        let checkInType: CheckInType
        let aiSummary: String?
    }

    /// Creates per-check-in summaries for timeline display.
    /// Uses label-based score fallback for mood.
    static func dailySummaries(from checkIns: [CheckIn]) -> [DailySummary] {
        checkIns.map { checkIn in
            let aiSummary = checkIn.aiSummary
            let fallbackMoodDescription = fallbackMoodDescription(from: aiSummary)
            let fallbackMoodScore = fallbackMoodScore(from: aiSummary)
            let fallbackSleepHours = fallbackSleepHours(from: aiSummary)
            let symptomNames = checkIn.symptoms.map { symptom -> String in
                if symptom.type == .other, let desc = symptom.userDescription, !desc.isEmpty {
                    return String(desc.prefix(30))
                }
                return symptom.type.rawValue
            }
            return DailySummary(
                date: checkIn.startedAt,
                moodScore: checkIn.mood?.score ?? scoreFallback(from: checkIn.mood?.label) ?? fallbackMoodScore,
                moodLabel: checkIn.mood?.label,
                moodDescription: checkIn.mood?.description ?? fallbackMoodDescription,
                sleepHours: checkIn.sleep?.hours ?? fallbackSleepHours,
                symptomCount: checkIn.symptoms.count,
                symptomNames: symptomNames,
                checkInType: checkIn.type,
                aiSummary: aiSummary
            )
        }
    }

    private static func fallbackMoodDescription(from aiSummary: String?) -> String? {
        guard let raw = captureField("Mood", from: aiSummary) else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: #"[^A-Za-z\s-]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned.capitalized
    }

    private static func fallbackMoodScore(from aiSummary: String?) -> Int? {
        guard let mood = fallbackMoodDescription(from: aiSummary)?.lowercased() else { return nil }

        switch mood {
        case let value where value.contains("great"),
             let value where value.contains("happy"),
             let value where value.contains("good"),
             let value where value.contains("calm"),
             let value where value.contains("better"):
            return 4
        case let value where value.contains("okay"),
             let value where value.contains("ok"),
             let value where value.contains("neutral"),
             let value where value.contains("fine"):
            return 3
        case let value where value.contains("tired"),
             let value where value.contains("anxious"),
             let value where value.contains("stressed"),
             let value where value.contains("low"),
             let value where value.contains("sad"),
             let value where value.contains("worse"):
            return 2
        default:
            return nil
        }
    }

    private static func fallbackSleepHours(from aiSummary: String?) -> Double? {
        guard let raw = captureField("Sleep", from: aiSummary)?.lowercased() else { return nil }

        if let numeric = raw.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) {
            return Double(raw[numeric])
        }

        let wordNumbers: [String: Double] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12,
        ]

        for (word, value) in wordNumbers {
            if raw.contains(word) {
                return value
            }
        }

        return nil
    }

    private static func captureField(_ field: String, from aiSummary: String?) -> String? {
        guard let aiSummary, !aiSummary.isEmpty else { return nil }
        let pattern = #"(?i)\#(field):\s*([^\.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(aiSummary.startIndex..<aiSummary.endIndex, in: aiSummary)
        guard
            let match = regex.firstMatch(in: aiSummary, options: [], range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: aiSummary)
        else {
            return nil
        }

        return String(aiSummary[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
