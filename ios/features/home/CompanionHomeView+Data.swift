import Foundation

extension CompanionHomeView {

    /// Load glow history and check-in progress from Firestore.
    func loadData() {
        guard let uid = authService.currentUser?.uid else {
            loadPlaceholderData()
            return
        }

        Task {
            await loadGlowHistory(userId: uid)
            await loadCheckInProgress(userId: uid)
        }
    }

    // MARK: - Glow History

    private func loadGlowHistory(userId: String) async {
        do {
            let checkIns: [CheckIn] = try await storageService.fetchAll(
                CheckIn.self,
                from: "checkins",
                userId: userId,
                limit: 50
            )
            let days = mapCheckInsToDays(checkIns)
            await MainActor.run { glowDays = days }
        } catch {
            print("[CompanionHomeView] Failed to load glow history: \(error)")
            await MainActor.run { loadPlaceholderData() }
        }
    }

    private func mapCheckInsToDays(_ checkIns: [CheckIn]) -> [GlowDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).reversed().map { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return GlowDay(id: today, status: .missed)
            }

            let dayCheckIns = checkIns.filter { checkIn in
                calendar.isDate(checkIn.startedAt, inSameDayAs: date)
                    && checkIn.completionStatus == .completed
            }

            if dayCheckIns.isEmpty {
                return GlowDay(id: date, status: .missed)
            }

            return GlowDay(id: date, status: aggregateStatus(dayCheckIns))
        }
    }

    private func aggregateStatus(_ checkIns: [CheckIn]) -> DayStatus {
        var hasNegative = false
        var hasPositive = false
        var hasSevereSymptom = false

        for checkIn in checkIns {
            if let mood = checkIn.mood {
                if let label = mood.label {
                    if label == "negative" { hasNegative = true }
                    if label == "positive" { hasPositive = true }
                } else if let score = mood.score {
                    if score <= 2 { hasNegative = true }
                    if score >= 4 { hasPositive = true }
                }
            }

            for symptom in checkIn.symptoms {
                if let severity = symptom.severity, severity >= 4 {
                    hasSevereSymptom = true
                }
                if symptom.comparedToYesterday == "worse" {
                    hasSevereSymptom = true
                }
            }
        }

        if hasSevereSymptom || (hasNegative && !hasPositive) {
            return .concern
        }
        if hasNegative || !hasPositive {
            return .mixed
        }
        return .good
    }

    // MARK: - Check-In Progress

    private func loadCheckInProgress(userId: String) async {
        do {
            let checkIns: [CheckIn] = try await storageService.fetchAll(
                CheckIn.self,
                from: "checkins",
                userId: userId,
                limit: 20
            )

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let todayCompleted = checkIns.filter { checkIn in
                calendar.isDate(checkIn.startedAt, inSameDayAs: today)
                    && checkIn.completionStatus == .completed
            }.count

            let total = max(3, todayCompleted)
            await MainActor.run {
                checkInProgress = CheckInProgress(completed: todayCompleted, total: total)
            }
        } catch {
            print("[CompanionHomeView] Failed to load check-in progress: \(error)")
        }
    }

    // MARK: - Debug Seed Data

    #if DEBUG
    static func seedDemoData(userId: String, storage: StorageService) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        struct Day {
            let ago: Int; let type: CheckInType
            let moodScore: Int; let moodLabel: String
            let sleepHours: Double; let sleepQuality: Int
            let symptoms: [SymptomEntry]
            let summary: String
        }

        let days: [Day] = [
            Day(ago: 6, type: .morning, moodScore: 4, moodLabel: "positive",
                sleepHours: 7.5, sleepQuality: 4,
                symptoms: [SymptomEntry(type: .tremor, severity: 2, comparedToYesterday: "same")],
                summary: "Good day overall. Mild tremor in the morning that eased after medication."),
            Day(ago: 5, type: .morning, moodScore: 3, moodLabel: "neutral",
                sleepHours: 6, sleepQuality: 3,
                symptoms: [SymptomEntry(type: .fatigue, severity: 3, comparedToYesterday: "worse")],
                summary: "Feeling tired after a rough night. Fatigue made it harder to focus."),
            Day(ago: 4, type: .morning, moodScore: 4, moodLabel: "positive",
                sleepHours: 8, sleepQuality: 4,
                symptoms: [],
                summary: "Great day, slept well. No symptoms to report."),
            Day(ago: 3, type: .morning, moodScore: 2, moodLabel: "negative",
                sleepHours: 5, sleepQuality: 2,
                symptoms: [SymptomEntry(type: .tremor, severity: 4, comparedToYesterday: "worse")],
                summary: "Tough day. Tremor much worse, barely slept. Feeling frustrated."),
            Day(ago: 2, type: .morning, moodScore: 3, moodLabel: "neutral",
                sleepHours: 7, sleepQuality: 3,
                symptoms: [SymptomEntry(type: .stiffness, severity: 3, comparedToYesterday: "same")],
                summary: "Moderate stiffness in hands and legs. Manageable with stretching."),
            Day(ago: 1, type: .morning, moodScore: 4, moodLabel: "positive",
                sleepHours: 7.5, sleepQuality: 4,
                symptoms: [SymptomEntry(type: .fatigue, severity: 2, comparedToYesterday: "better")],
                summary: "Feeling much better. Mild fatigue but otherwise a good day."),
            Day(ago: 0, type: .morning, moodScore: 5, moodLabel: "positive",
                sleepHours: 8, sleepQuality: 5,
                symptoms: [],
                summary: "Best day this week. Slept well, no symptoms. Went for a walk."),
        ]

        for day in days {
            guard let date = calendar.date(byAdding: .day, value: -day.ago, to: today) else { continue }
            let startedAt = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: date) ?? date
            let completedAt = startedAt.addingTimeInterval(180)

            var checkIn = CheckIn(userId: userId, type: day.type, pipelineMode: "live")
            checkIn.startedAt = startedAt
            checkIn.completedAt = completedAt
            checkIn.completionStatus = .completed
            checkIn.durationSeconds = 180
            checkIn.mood = MoodEntry(score: day.moodScore, label: day.moodLabel)
            checkIn.sleep = SleepEntry(hours: day.sleepHours, quality: day.sleepQuality)
            checkIn.symptoms = day.symptoms
            checkIn.aiSummary = day.summary

            do {
                _ = try await storage.save(checkIn, to: "checkins", userId: userId)
            } catch {
                print("[SeedData] Failed to save check-in \(day.ago)d ago: \(error)")
            }
        }
        print("[SeedData] Seeded 7 days of demo check-ins")
    }

    static func clearCheckIns(userId: String, storage: StorageService) async {
        do {
            let checkIns: [CheckIn] = try await storage.fetchAll(
                CheckIn.self, from: "checkins", userId: userId, limit: 200
            )
            for checkIn in checkIns {
                guard let id = checkIn.id else { continue }
                try await storage.delete(from: "checkins", userId: userId, documentId: id)
            }
            print("[SeedData] Cleared \(checkIns.count) check-ins")
        } catch {
            print("[SeedData] Failed to clear check-ins: \(error)")
        }
    }
    #endif

    // MARK: - Placeholder

    private func loadPlaceholderData() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        glowDays = (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return GlowDay(id: date, status: .missed)
        }
        checkInProgress = CheckInProgress(completed: 0, total: 3)
    }
}
