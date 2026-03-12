import SwiftUI
import AVFoundation

/// Unified reminders screen: check-ins, medications, and custom reminders
/// grouped by time of day (Morning / Afternoon / Evening).
struct RemindersView: View {
    @EnvironmentObject var checkInScheduleService: CheckInScheduleService
    @EnvironmentObject var medicationService: MedicationService
    @EnvironmentObject var customReminderService: CustomReminderService
    @EnvironmentObject var voiceMessageInboxService: VoiceMessageInboxService
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var theme: ThemeService

    @State private var showingAddSheet = false
    @State private var showingAddMedSheet = false
    @State private var showingAddCustomSheet = false
    @State private var showingCheckInSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        let items = buildUnifiedList()

                        if voiceMessageInboxService.messages.isEmpty && items.isEmpty {
                            emptyState
                        } else {
                            if !voiceMessageInboxService.messages.isEmpty {
                                VoiceMessagesCard(messages: voiceMessageInboxService.messages)
                                    .environmentObject(voiceMessageInboxService)
                                    .environmentObject(theme)
                            }
                            ForEach(TimeWindow.allCases) { window in
                                let windowItems = items.filter { $0.window == window }
                                if !windowItems.isEmpty {
                                    sectionCard(window: window, items: windowItems)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .screenBackground()
            .navigationTitle("Reminders")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                            .frame(minWidth: 60, minHeight: 60)
                    }
                    .tint(.white)
                    .accessibilityLabel("Add reminder")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ReminderAddView(
                    onMedication: { showingAddMedSheet = true },
                    onCheckIn: { showingCheckInSettings = true },
                    onCustom: { showingAddCustomSheet = true }
                )
                .environmentObject(theme)
            }
            .sheet(isPresented: $showingAddMedSheet) {
                MedicationEditView(medication: nil)
                    .environmentObject(medicationService)
            }
            .sheet(isPresented: $showingAddCustomSheet) {
                CustomReminderEditView(existing: nil)
                    .environmentObject(customReminderService)
            }
            .sheet(isPresented: $showingCheckInSettings) {
                checkInSettingsSheet
            }
        }
        .task {
            await medicationService.fetchMedications()
            await customReminderService.fetchReminders()
            await voiceMessageInboxService.fetchMessages()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.waveform.right")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.6))

            Text("No reminders or voice messages yet")
                .font(.headline)
                .foregroundColor(.white)

            Text("Tap + to add a medication, check-in, or custom reminder. Caregiver voice messages will also appear here.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Time-Grouped Section

    private func sectionCard(window: TimeWindow, items: [ReminderItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(window.label, systemImage: window.icon)
                .font(.headline)
                .foregroundColor(.white)

            ForEach(items) { item in
                reminderRow(item)
                if item.id != items.last?.id {
                    Divider()
                }
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private func reminderRow(_ item: ReminderItem) -> some View {
        switch item.kind {
        case .medication(let med):
            MedicationReminderRow(medication: med)
        case .checkIn(let label, let time):
            checkInRow(label: label, time: time)
        case .custom(let reminder):
            CustomReminderRow(reminder: reminder)
        }
    }

    // MARK: - Check-In Row

    private func checkInRow(label: String, time: String) -> some View {
        Button {
            showingCheckInSettings = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.title3)
                    .foregroundColor(theme.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(label) Check-In")
                        .font(.body.weight(.medium))
                        .foregroundColor(theme.text)

                    Text(time)
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .frame(minHeight: 48)
        }
        .accessibilityLabel("\(label) check-in at \(time)")
    }

    // MARK: - Check-In Settings Sheet

    private var checkInSettingsSheet: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        scheduleRow(
                            label: "Morning",
                            enabled: $checkInScheduleService.schedule.morningEnabled,
                            time: Binding(
                                get: { timeFromString(checkInScheduleService.schedule.morningTime ?? "08:00") },
                                set: { checkInScheduleService.schedule.morningTime = timeToString($0) }
                            )
                        )

                        Divider()

                        scheduleRow(
                            label: "Evening",
                            enabled: $checkInScheduleService.schedule.eveningEnabled,
                            time: Binding(
                                get: { timeFromString(checkInScheduleService.schedule.eveningTime ?? "20:00") },
                                set: { checkInScheduleService.schedule.eveningTime = timeToString($0) }
                            )
                        )
                    }
                    .padding(20)
                    .glassCard()
                }
            }
            .screenBackground()
            .navigationTitle("Check-In Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingCheckInSettings = false }
                        .frame(minWidth: 60, minHeight: 60)
                }
            }
            .onChange(of: checkInScheduleService.schedule.morningEnabled) { _ in scheduleDidChange() }
            .onChange(of: checkInScheduleService.schedule.eveningEnabled) { _ in scheduleDidChange() }
            .onChange(of: checkInScheduleService.schedule.morningTime) { _ in scheduleDidChange() }
            .onChange(of: checkInScheduleService.schedule.eveningTime) { _ in scheduleDidChange() }
        }
    }

    private func scheduleRow(label: String, enabled: Binding<Bool>, time: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            Toggle(label, isOn: enabled)
                .font(.body)
                .foregroundColor(theme.text)
                .frame(minHeight: 60)
                .tint(theme.primary)
                .accessibilityLabel("\(label) check-in")

            if enabled.wrappedValue {
                DatePicker(
                    "",
                    selection: time,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .frame(minHeight: 60)
                .accessibilityLabel("\(label) time")
            }
        }
    }

    private func scheduleDidChange() {
        Task {
            await notificationService.requestPermission()
            await checkInScheduleService.saveSchedule()
            await checkInScheduleService.scheduleCheckInNotifications()
        }
    }

    // MARK: - Build Unified List

    private func buildUnifiedList() -> [ReminderItem] {
        var items: [ReminderItem] = []

        // Check-in entries
        if checkInScheduleService.schedule.morningEnabled,
           let time = checkInScheduleService.schedule.morningTime {
            items.append(ReminderItem(
                kind: .checkIn(label: "Morning", time: time),
                sortTime: time
            ))
        }
        if checkInScheduleService.schedule.eveningEnabled,
           let time = checkInScheduleService.schedule.eveningTime {
            items.append(ReminderItem(
                kind: .checkIn(label: "Evening", time: time),
                sortTime: time
            ))
        }

        // Medication entries (one per scheduled time)
        for med in medicationService.medications where med.isActive {
            let earliest = med.schedule.sorted().first ?? "12:00"
            items.append(ReminderItem(
                kind: .medication(med),
                sortTime: earliest
            ))
        }

        // Custom reminder entries
        for reminder in customReminderService.reminders {
            let earliest = reminder.schedule.sorted().first ?? "12:00"
            items.append(ReminderItem(
                kind: .custom(reminder),
                sortTime: earliest
            ))
        }

        return items.sorted { $0.sortTime < $1.sortTime }
    }

    // MARK: - Time Helpers

    private func timeFromString(_ time: String) -> Date {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func timeToString(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}

// MARK: - Time Windows

private enum TimeWindow: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .evening: return "moon"
        }
    }

    static func from(time: String) -> TimeWindow {
        let parts = time.split(separator: ":")
        guard let hour = parts.first.flatMap({ Int($0) }) else { return .morning }
        if hour < 12 { return .morning }
        if hour < 17 { return .afternoon }
        return .evening
    }
}

// MARK: - Unified Reminder Item

private struct ReminderItem: Identifiable {
    let id = UUID()
    let kind: ReminderKind
    let sortTime: String

    var window: TimeWindow { TimeWindow.from(time: sortTime) }
}

private enum ReminderKind {
    case medication(Medication)
    case checkIn(label: String, time: String)
    case custom(CustomReminder)
}

// MARK: - Medication Row

private struct MedicationReminderRow: View {
    let medication: Medication
    @EnvironmentObject var medicationService: MedicationService
    @EnvironmentObject var theme: ThemeService

    @State private var showingEditSheet = false

    var body: some View {
        Button {
            showingEditSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: formIcon)
                    .font(.title3)
                    .foregroundColor(theme.primary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(medication.name)
                        .font(.body.weight(.medium))
                        .foregroundColor(theme.text)

                    if let dosage = medication.dosage, !dosage.isEmpty {
                        Text(dosage)
                            .font(.caption)
                            .foregroundColor(theme.textSecondary)
                    }
                }

                Spacer()

                if medication.reminderEnabled {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundColor(theme.primary)
                }

                if !medication.schedule.isEmpty {
                    Text(medication.schedule.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: 48)
        }
        .accessibilityLabel("\(medication.name), \(medication.dosage ?? "")")
        .sheet(isPresented: $showingEditSheet) {
            MedicationEditView(medication: medication)
                .environmentObject(medicationService)
        }
    }

    private var formIcon: String {
        switch medication.form {
        case "pill": return "pills.fill"
        case "injection": return "syringe.fill"
        case "patch": return "bandage.fill"
        default: return "pills"
        }
    }
}

// MARK: - Custom Reminder Row

private struct CustomReminderRow: View {
    let reminder: CustomReminder
    @EnvironmentObject var customReminderService: CustomReminderService
    @EnvironmentObject var theme: ThemeService

    @State private var showingEditSheet = false

    var body: some View {
        Button {
            showingEditSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(reminder.title)
                            .font(.body.weight(.medium))
                            .foregroundColor(theme.text)

                        if reminder.createdBy.role == .caregiver {
                            Text("Caregiver")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.accent)
                                .cornerRadius(4)
                        }
                    }

                    if let note = reminder.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !reminder.isEnabled {
                    Image(systemName: "bell.slash")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }

                if !reminder.schedule.isEmpty {
                    Text(reminder.schedule.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: 48)
        }
        .accessibilityLabel(reminder.title)
        .sheet(isPresented: $showingEditSheet) {
            CustomReminderEditView(existing: reminder)
                .environmentObject(customReminderService)
        }
    }
}

private struct VoiceMessagesCard: View {
    let messages: [VoiceMessage]

    @EnvironmentObject var voiceMessageInboxService: VoiceMessageInboxService
    @EnvironmentObject var theme: ThemeService

    @State private var audioPlayer: AVAudioPlayer?
    @State private var playingMessageId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Voice Messages", systemImage: "waveform.badge.mic")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(messages.prefix(5)) { message in
                voiceMessageRow(message)
                if message.id != messages.prefix(5).last?.id {
                    Divider()
                }
            }
        }
        .glassCard()
        .onDisappear {
            audioPlayer?.stop()
            audioPlayer = nil
            playingMessageId = nil
        }
    }

    @ViewBuilder
    private func voiceMessageRow(_ message: VoiceMessage) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await play(message)
                }
            } label: {
                Image(systemName: playingMessageId == message.id ? "stop.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(theme.primary)
                    .frame(width: 36, height: 36)
                    .background(theme.primary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(message.caregiverName ?? "Caregiver")
                        .font(.body.weight(.medium))
                        .foregroundColor(theme.text)
                    if message.isUnread {
                        Text("New")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.accent)
                            .cornerRadius(4)
                    }
                }

                Text(message.transcript?.isEmpty == false ? message.transcript! : "Tap play to listen.")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)

                Text("\(formatDuration(message.durationSeconds)) · \(formatDate(message.createdAt))")
                    .font(.caption2)
                    .foregroundColor(theme.textSecondary.opacity(0.8))
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func play(_ message: VoiceMessage) async {
        guard let id = message.id else { return }

        if playingMessageId == id {
            audioPlayer?.stop()
            audioPlayer = nil
            playingMessageId = nil
            return
        }

        guard let data = Data(base64Encoded: message.audioBase64) else { return }

        do {
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            playingMessageId = id
            if message.isUnread {
                await voiceMessageInboxService.markAsListened(message)
            }
        } catch {
            print("[VoiceMessagesCard] Failed to play voice message: \(error)")
        }
    }

    private func formatDuration(_ value: Double) -> String {
        let rounded = max(1, Int(value.rounded()))
        return "\(rounded)s"
    }

    private func formatDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "Just now" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
