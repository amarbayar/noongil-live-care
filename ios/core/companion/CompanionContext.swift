import Foundation

/// Builds plain-text context strings for system prompts. Provider-agnostic — just string building.
enum CompanionContext {

    /// Builds a full context string from user data, appended to the system prompt.
    static func build(
        profile: UserProfile?,
        recentCheckIns: [CheckIn],
        medications: [Medication],
        vocabulary: VocabularyMap?,
        companionName: String = "Mira"
    ) -> String {
        var sections: [String] = []

        sections.append(buildIdentitySection(profile: profile, companionName: companionName))
        sections.append(buildTimeSection(profile: profile))

        if !recentCheckIns.isEmpty {
            sections.append(buildRecentCheckInsSection(recentCheckIns))
        }

        if recentCheckIns.count >= 2 {
            let patterns = buildPatternsSection(recentCheckIns)
            if !patterns.isEmpty {
                sections.append(patterns)
            }
        }

        if !medications.isEmpty {
            sections.append(buildMedicationsSection(medications, vocabulary: vocabulary))
        }

        if let vocabulary = vocabulary, !vocabulary.symptomWords.isEmpty || !vocabulary.moodWords.isEmpty {
            sections.append(buildVocabularySection(vocabulary))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Sections

    private static func buildIdentitySection(profile: UserProfile?, companionName: String) -> String {
        var lines = ["[Context]"]
        lines.append("Your name is \(companionName).")
        if let name = profile?.displayName {
            lines.append("The member's name is \(name).")
        }
        return lines.joined(separator: "\n")
    }

    private static func buildTimeSection(profile: UserProfile?) -> String {
        PromptService.buildRightNowContext()
    }

    private static func buildRecentCheckInsSection(_ checkIns: [CheckIn]) -> String {
        var lines = ["[Recent Check-ins]"]
        let recent = Array(checkIns.prefix(3))

        for checkIn in recent {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, h:mm a"
            let dateStr = dateFormatter.string(from: checkIn.startedAt)

            var summary = "\(dateStr) (\(checkIn.type.rawValue))"
            if let score = checkIn.mood?.score {
                summary += " — mood: \(moodLabel(score))"
            }
            if !checkIn.symptoms.isEmpty {
                let symptomNames = checkIn.symptoms.map { $0.type.rawValue }
                summary += " — mentioned: \(symptomNames.joined(separator: ", "))"
            }
            lines.append("- \(summary)")
        }
        return lines.joined(separator: "\n")
    }

    private static func buildMedicationsSection(_ medications: [Medication], vocabulary: VocabularyMap?) -> String {
        var lines = ["[Active Medications]"]
        let active = medications.filter { $0.isActive }

        for med in active {
            var entry = "- \(med.name)"
            if !med.schedule.isEmpty {
                entry += " at \(med.schedule.joined(separator: ", "))"
            }
            if let vocab = vocabulary {
                let nicknames = vocab.medicationNicknames.filter { $0.value == med.id }
                if let nickname = nicknames.first?.key {
                    entry += " [user calls it \"\(nickname)\"]"
                }
            }
            lines.append(entry)
        }
        return lines.joined(separator: "\n")
    }

    private static func buildVocabularySection(_ vocabulary: VocabularyMap) -> String {
        var lines = ["[Vocabulary Preferences — use the member's own words]"]

        for (word, type) in vocabulary.symptomWords {
            lines.append("- When referring to \(type), say \"\(word)\"")
        }
        for (word, label) in vocabulary.moodWords {
            lines.append("- When referring to \(label) mood, say \"\(word)\"")
        }
        for (word, _) in vocabulary.painWords {
            lines.append("- When referring to pain, say \"\(word)\"")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Greeting Context (B-03)

    /// Builds context hints for the greeting prompt: streaks, gaps, yesterday's mood.
    static func buildGreetingContext(
        recentCheckIns: [CheckIn],
        userName: String?,
        checkInType: CheckInType
    ) -> String {
        var hints: [String] = []

        let timeLabel = checkInType == .evening ? "evening" : "morning"
        if let name = userName, !name.isEmpty {
            hints.append("This is a \(timeLabel) check-in with \(name).")
        } else {
            hints.append("This is a \(timeLabel) check-in.")
        }

        let completed = recentCheckIns.filter { $0.completionStatus == .completed }

        if completed.isEmpty {
            hints.append("This is their first check-in ever — welcome them warmly.")
            return hints.joined(separator: " ")
        }

        // Streak: count consecutive days with check-ins (including today)
        let streak = calculateStreak(checkIns: completed)
        if streak >= 3 {
            hints.append("\(streak)-day check-in streak — acknowledge it briefly.")
        }

        // Gap: days since last check-in
        if let lastDate = completed.first?.startedAt {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            if daysSince >= 2 {
                hints.append("It's been \(daysSince) days since their last check-in — welcome them back gently, no guilt.")
            }
        }

        // Yesterday's mood
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayCheckIns = completed.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: yesterday) }
        if let lastMood = yesterdayCheckIns.first?.mood {
            if let score = lastMood.score, score <= 2 {
                hints.append("Yesterday was a rough day (mood \(score)/5) — acknowledge it with empathy.")
            } else if let score = lastMood.score, score >= 4 {
                hints.append("Yesterday was a good day (mood \(score)/5) — you can reference that positively.")
            }
        }

        return hints.joined(separator: " ")
    }

    // MARK: - Closing Context (B-04)

    /// Builds context hints for the closing prompt: positive data points to celebrate.
    static func buildClosingContext(
        currentCheckIn: CheckIn?,
        recentCheckIns: [CheckIn]
    ) -> String {
        var hints: [String] = []

        hints.append("End with a warm, encouraging observation.")

        // Streak
        let completed = recentCheckIns.filter { $0.completionStatus == .completed }
        let streak = calculateStreak(checkIns: completed)
        if streak >= 2 {
            hints.append("They're on a \(streak)-day streak — that's worth celebrating.")
        }

        // Sleep improving
        if let currentSleep = currentCheckIn?.sleep?.hours, recentCheckIns.count >= 2 {
            let previousSleep = recentCheckIns.dropFirst().compactMap { $0.sleep?.hours }
            if let prevAvg = previousSleep.isEmpty ? nil : previousSleep.reduce(0, +) / Double(previousSleep.count) {
                if currentSleep > prevAvg + 0.5 {
                    hints.append("Their sleep seems to be improving (rest is up).")
                }
            }
        }

        // Mood improvement
        if let currentMood = currentCheckIn?.mood?.score, recentCheckIns.count >= 2 {
            if let previousMood = recentCheckIns.dropFirst().first?.mood?.score {
                if currentMood > previousMood {
                    hints.append("Mood is better than last time — note the improvement.")
                }
            }
        }

        // General warmth fallback
        if hints.count == 1 {
            hints.append("Reference something specific they shared today, or offer general warmth and thanks for checking in.")
        }

        hints.append("Never end on a clinical note. Keep it to 1-2 sentences.")

        return hints.joined(separator: " ")
    }

    // MARK: - Streak Calculation

    /// Counts consecutive days with completed check-ins, working backwards from today.
    static func calculateStreak(checkIns: [CheckIn]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Collect unique days that have check-ins
        var checkInDays = Set<Date>()
        for checkIn in checkIns {
            let day = calendar.startOfDay(for: checkIn.startedAt)
            checkInDays.insert(day)
        }

        var streak = 0
        var currentDay = today

        while checkInDays.contains(currentDay) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else { break }
            currentDay = previousDay
        }

        return streak
    }

    static func buildPatternsSection(_ checkIns: [CheckIn]) -> String {
        var lines = ["[Patterns Observed — reference naturally, never lecture]"]
        let recent = Array(checkIns.prefix(3))

        // Mood trend: compare latest to previous (qualitative only)
        if recent.count >= 2 {
            let latestMood = recent[0].mood?.score
            let previousMood = recent[1].mood?.score
            if let latest = latestMood, let previous = previousMood {
                if latest < previous {
                    lines.append("- Mood has dipped since last check-in (\(moodLabel(previous)) → \(moodLabel(latest)))")
                } else if latest > previous {
                    lines.append("- Mood has improved since last check-in (\(moodLabel(previous)) → \(moodLabel(latest)))")
                }
            }
        }

        // Sleep trend: latest vs average of recent
        let sleepHours = recent.compactMap { $0.sleep?.hours }
        if sleepHours.count >= 2 {
            let latest = sleepHours[0]
            let avg = sleepHours.dropFirst().reduce(0.0, +) / Double(sleepHours.count - 1)
            let diff = latest - avg
            if diff < -1.0 {
                lines.append("- Slept less than usual last night (\(String(format: "%.1f", latest))h vs \(String(format: "%.1f", avg))h avg)")
            } else if diff > 1.0 {
                lines.append("- Slept more than usual last night (\(String(format: "%.1f", latest))h vs \(String(format: "%.1f", avg))h avg)")
            }
        }

        // Recurring symptoms: mentioned in 2+ of last N check-ins
        var symptomCounts: [SymptomType: Int] = [:]
        for checkIn in recent {
            for symptom in checkIn.symptoms {
                symptomCounts[symptom.type, default: 0] += 1
            }
        }
        let recurring = symptomCounts.filter { $0.value >= 2 }.map { $0.key.rawValue }
        if !recurring.isEmpty {
            lines.append("- Recurring: \(recurring.joined(separator: ", ")) (mentioned in multiple recent check-ins)")
        }

        // Only return if we found patterns beyond the header
        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    // MARK: - Helpers

    /// Maps a numeric mood score (1-5) to a qualitative label for prompt minimization.
    static func moodLabel(_ score: Int) -> String {
        switch score {
        case 1...2: return "low"
        case 3: return "moderate"
        case 4...5: return "good"
        default: return "moderate"
        }
    }
}
