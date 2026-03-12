import SwiftUI

/// Combined journal view — compact trend summary at top, chronological check-in list below.
/// Voice-first companion — read-only journal, not a data entry form.
struct HealthHistoryView: View {
    @EnvironmentObject var theme: ThemeService
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var authService: AuthService

    @State private var checkIns: [CheckIn] = []
    @State private var isLoading = true
    @State private var expandedCheckInIndex: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                CompanionHomeBackgroundStyle.make(for: .listening).gradient
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if checkIns.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            trendsSection
                            checkInsSection
                        }
                        .padding(20)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ReportView()
                    } label: {
                        Image(systemName: "doc.text")
                            .foregroundColor(.white)
                            .accessibilityLabel("Health summary report")
                    }
                }
            }
            .task {
                await loadCheckIns()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.6))

            Text("No check-ins yet")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)

            Text("After your first check-in with Mira, your health journal will appear here.")
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Trends Section

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("This Week", icon: "chart.line.uptrend.xyaxis")

            // Mini stat cards: Mood + Rest side by side
            HStack(spacing: 12) {
                moodStatCard.staggeredAppear(index: 0)
                sleepStatCard.staggeredAppear(index: 1)
            }

            // Top symptoms as horizontal pills
            let symptoms = HealthHistoryService.symptomSummary(from: checkIns)
            if !symptoms.isEmpty {
                symptomPills(symptoms: Array(symptoms.prefix(5)))
            }
        }
    }

    private var moodStatCard: some View {
        VStack(spacing: 6) {
            if let avg = HealthHistoryService.averageMood(from: checkIns) {
                Text(moodEmoji(for: Int(avg.rounded())))
                    .font(.title)
                Text(String(format: "%.1f", avg))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(theme.text)
                Text("Mood")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
            } else {
                Text("--")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(theme.textSecondary)
                Text("Mood")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard()
    }

    private var sleepStatCard: some View {
        VStack(spacing: 6) {
            if let avg = HealthHistoryService.averageSleep(from: checkIns) {
                Image(systemName: "moon.zzz")
                    .font(.title2)
                    .foregroundColor(sleepColor(for: avg))
                Text(String(format: "%.1f", avg) + "h")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(theme.text)
                Text("Rest")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
            } else {
                Text("--")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(theme.textSecondary)
                Text("Rest")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard()
    }

    private func symptomPills(symptoms: [HealthHistoryService.SymptomSummary]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(symptoms.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(severityColor(for: item.averageSeverity))
                            .frame(width: 6, height: 6)
                        Text(symptomDisplayName(item.type, userDescription: item.latestDescription))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                        Text("\(item.occurrences)×")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.15))
                    .clipShape(Capsule())
                    .staggeredAppear(index: index)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Top symptoms: \(symptoms.map { symptomDisplayName($0.type, userDescription: $0.latestDescription) }.joined(separator: ", "))")
    }

    // MARK: - Check-ins Section

    private var checkInsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Check-ins", icon: "clock")

            let summaries = HealthHistoryService.dailySummaries(from: checkIns)

            ForEach(Array(summaries.enumerated()), id: \.offset) { index, summary in
                checkInRow(summary, index: index)
            }
        }
    }

    private func checkInRow(_ summary: HealthHistoryService.DailySummary, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: type icon
            VStack(spacing: 2) {
                Image(systemName: checkInIcon(summary.checkInType))
                    .font(.body)
                    .foregroundColor(theme.primary)
                    .frame(width: 28, height: 28)
            }

            // Middle: details
            VStack(alignment: .leading, spacing: 4) {
                // Date + type badge
                HStack(spacing: 6) {
                    Text(dateLabel(summary.date))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.text)

                    Text(checkInTypeBadge(summary.checkInType))
                        .font(.caption2)
                        .foregroundColor(theme.textSecondary)
                }

                // Mood line
                if let score = summary.moodScore {
                    HStack(spacing: 4) {
                        Text(moodEmoji(for: score))
                            .font(.callout)
                        if let desc = summary.moodDescription, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundColor(theme.textSecondary)
                                .lineLimit(1)
                        } else if let label = summary.moodLabel {
                            Text(label.capitalized)
                                .font(.caption)
                                .foregroundColor(theme.textSecondary)
                        }
                    }
                    MoodColorBar(score: score)
                        .padding(.top, 2)
                }

                // Sleep line
                if let hours = summary.sleepHours {
                    Text("\(String(format: "%.0f", hours))h sleep")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                    SleepColorBar(hours: hours)
                        .padding(.top, 2)
                }

                // Symptoms line
                if !summary.symptomNames.isEmpty {
                    Text(summary.symptomNames.map { symptomDisplayNameFromRaw($0) }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }

                // AI summary snippet
                if let aiSummary = summary.aiSummary, !aiSummary.isEmpty {
                    Text(aiSummary)
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(expandedCheckInIndex == index ? nil : 2)
                        .italic()
                        .animation(.easeInOut(duration: 0.2), value: expandedCheckInIndex)
                }
            }

            Spacer()

            // Right: mood color dot
            if let score = summary.moodScore {
                Circle()
                    .fill(moodColor(for: score))
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(minHeight: 60)
        .glassCard()
        .contentShape(Rectangle())
        .onTapGesture {
            guard summary.aiSummary != nil, !(summary.aiSummary ?? "").isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedCheckInIndex = expandedCheckInIndex == index ? nil : index
            }
        }
        .staggeredAppear(index: index)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.white)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
        }
    }

    // MARK: - Helpers

    private func checkInIcon(_ type: CheckInType) -> String {
        switch type {
        case .morning: return "sunrise"
        case .evening: return "sunset"
        case .adhoc: return "bubble.left"
        }
    }

    private func checkInTypeBadge(_ type: CheckInType) -> String {
        switch type {
        case .morning: return "Morning"
        case .evening: return "Evening"
        case .adhoc: return "Ad-hoc"
        }
    }

    private func moodEmoji(for score: Int) -> String {
        switch score {
        case 1: return "😔"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return "😐"
        }
    }

    private func moodColor(for score: Int) -> Color {
        switch score {
        case 1, 2: return theme.error
        case 3: return theme.warning
        case 4, 5: return theme.success
        default: return theme.textSecondary
        }
    }

    private func sleepColor(for hours: Double) -> Color {
        switch hours {
        case ..<5: return theme.error
        case 5..<7: return theme.warning
        default: return theme.success
        }
    }

    private func severityColor(for severity: Double?) -> Color {
        guard let s = severity else { return theme.textSecondary }
        switch s {
        case ..<2.5: return theme.success
        case 2.5..<3.5: return theme.warning
        default: return theme.error
        }
    }

    private func symptomDisplayName(_ type: SymptomType, userDescription: String? = nil) -> String {
        if type == .other, let desc = userDescription, !desc.isEmpty {
            return String(desc.prefix(30))
        }
        switch type {
        case .tremor: return "Tremor"
        case .rigidity: return "Rigidity"
        case .pain: return "Pain"
        case .fatigue: return "Fatigue"
        case .dizziness: return "Dizziness"
        case .nausea: return "Nausea"
        case .headache: return "Headache"
        case .numbness: return "Numbness"
        case .weakness: return "Weakness"
        case .cramping: return "Cramping"
        case .stiffness: return "Stiffness"
        case .balanceIssues: return "Balance"
        case .speechDifficulty: return "Speech"
        case .swallowingDifficulty: return "Swallowing"
        case .breathingDifficulty: return "Breathing"
        case .other: return "Other"
        }
    }

    /// Converts raw type strings from DailySummary.symptomNames to display names.
    /// symptomNames already contains user descriptions for .other type.
    private func symptomDisplayNameFromRaw(_ rawName: String) -> String {
        if let type = SymptomType(rawValue: rawName) {
            return symptomDisplayName(type)
        }
        // Already a user description (from .other with userDescription)
        return rawName
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Data Loading

    private func loadCheckIns() async {
        guard let uid = authService.currentUser?.uid else {
            isLoading = false
            return
        }

        do {
            checkIns = try await storageService.fetchAll(
                CheckIn.self,
                from: "checkins",
                userId: uid,
                limit: 30
            )
            // Sort newest first (Firestore returns default order)
            checkIns.sort { $0.startedAt > $1.startedAt }
        } catch {
            print("[HealthHistoryView] Error loading check-ins: \(error)")
        }

        isLoading = false
    }
}
