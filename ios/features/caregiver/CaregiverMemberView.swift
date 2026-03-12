import SwiftUI

/// Caregiver's view of a linked member's reminders.
/// Shows medications, check-in schedule, and custom reminders fetched via backend API.
struct CaregiverMemberView: View {
    @EnvironmentObject var theme: ThemeService

    let member: CaregiverMember
    let caregiverService: CaregiverService

    @State private var reminders: MemberRemindersResponse?
    @State private var isLoading = true
    @State private var showingAddReminder = false
    @State private var showingDataSharingAgreement = false
    @State private var newTitle = ""
    @State private var newNote = ""
    @State private var newTime = "12:00"
    @AppStorage("caregiverDataSharingAgreed") private var dataSharingAgreed = false

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let data = reminders {
                ScrollView {
                    VStack(spacing: 20) {
                        checkInScheduleCard(data.checkInSchedule)
                        medicationsCard(data.medications)
                        customRemindersCard(data.customReminders)
                    }
                    .padding(.vertical, 16)
                }
            } else {
                Text("Could not load reminders")
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .screenBackground()
        .navigationTitle(member.memberName ?? "Member")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddReminder = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(minWidth: 60, minHeight: 60)
                }
                .tint(.white)
                .accessibilityLabel("Add reminder for member")
            }
        }
        .sheet(isPresented: $showingAddReminder) {
            addReminderSheet
        }
        .task {
            if !dataSharingAgreed {
                showingDataSharingAgreement = true
            }
            await loadReminders()
        }
        .sheet(isPresented: $showingDataSharingAgreement) {
            dataSharingAgreementSheet
        }
    }

    // MARK: - Check-In Schedule

    private func checkInScheduleCard(_ schedule: [String: AnyCodable]?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Check-In Schedule", systemImage: "bell")
                .font(.headline)
                .foregroundColor(theme.text)

            if let sched = schedule {
                let morningEnabled = (sched["morningEnabled"]?.value as? Bool) ?? false
                let eveningEnabled = (sched["eveningEnabled"]?.value as? Bool) ?? false
                let morningTime = (sched["morningTime"]?.value as? String) ?? "08:00"
                let eveningTime = (sched["eveningTime"]?.value as? String) ?? "20:00"

                if morningEnabled {
                    infoRow(icon: "sunrise", label: "Morning", detail: morningTime)
                }
                if eveningEnabled {
                    infoRow(icon: "moon", label: "Evening", detail: eveningTime)
                }
                if !morningEnabled && !eveningEnabled {
                    Text("No check-ins scheduled")
                        .font(.subheadline)
                        .foregroundColor(theme.textSecondary)
                }
            } else {
                Text("No check-in schedule set")
                    .font(.subheadline)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .glassCard()
    }

    // MARK: - Medications

    private func medicationsCard(_ meds: [[String: AnyCodable]]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Medications", systemImage: "pill")
                .font(.headline)
                .foregroundColor(theme.text)

            if meds.isEmpty {
                Text("No active medications")
                    .font(.subheadline)
                    .foregroundColor(theme.textSecondary)
            } else {
                ForEach(Array(meds.enumerated()), id: \.offset) { _, med in
                    let name = (med["name"]?.value as? String) ?? "Unknown"
                    let dosage = med["dosage"]?.value as? String
                    let schedule = (med["schedule"]?.value as? [Any])?.compactMap { $0 as? String } ?? []

                    infoRow(
                        icon: "pills.fill",
                        label: name,
                        detail: [dosage, schedule.isEmpty ? nil : schedule.joined(separator: ", ")]
                            .compactMap { $0 }.joined(separator: " · ")
                    )
                }
            }
        }
        .glassCard()
    }

    // MARK: - Custom Reminders

    private func customRemindersCard(_ customs: [[String: AnyCodable]]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Custom Reminders", systemImage: "star")
                .font(.headline)
                .foregroundColor(theme.text)

            if customs.isEmpty {
                Text("No custom reminders")
                    .font(.subheadline)
                    .foregroundColor(theme.textSecondary)
            } else {
                ForEach(Array(customs.enumerated()), id: \.offset) { _, rem in
                    let title = (rem["title"]?.value as? String) ?? "Reminder"
                    let note = rem["note"]?.value as? String
                    let schedule = (rem["schedule"]?.value as? [Any])?.compactMap { $0 as? String } ?? []
                    let isEnabled = (rem["isEnabled"]?.value as? Bool) ?? true
                    let createdBy = rem["createdBy"]?.value as? [String: Any]
                    let role = createdBy?["role"] as? String

                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(title)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(theme.text)

                                if role == "caregiver" {
                                    Text("Caregiver")
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(theme.accent)
                                        .cornerRadius(4)
                                }
                            }

                            if let note = note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundColor(theme.textSecondary)
                            }
                        }

                        Spacer()

                        if !isEnabled {
                            Image(systemName: "bell.slash")
                                .font(.caption)
                                .foregroundColor(theme.textSecondary)
                        }

                        if !schedule.isEmpty {
                            Text(schedule.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(minHeight: 48)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Add Reminder Sheet

    private var addReminderSheet: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.text)

                            TextField("e.g. Drink water", text: $newTitle)
                                .font(.body)
                                .padding(12)
                                .background(theme.surface)
                                .cornerRadius(10)
                                .frame(minHeight: 48)
                        }
                        .glassCard()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note (optional)")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.text)

                            TextField("Additional details", text: $newNote)
                                .font(.body)
                                .padding(12)
                                .background(theme.surface)
                                .cornerRadius(10)
                                .frame(minHeight: 48)
                        }
                        .glassCard()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Time")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.text)

                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { timeFromString(newTime) },
                                    set: { newTime = timeToString($0) }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .frame(minHeight: 48)
                        }
                        .glassCard()
                    }
                    .padding(20)
                }
            }
            .screenBackground()
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showingAddReminder = false }
                        .frame(minWidth: 60, minHeight: 60)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            let success = await caregiverService.addReminderForMember(
                                memberId: member.memberId,
                                title: newTitle,
                                note: newNote.isEmpty ? nil : newNote,
                                schedule: [newTime]
                            )
                            if success {
                                showingAddReminder = false
                                newTitle = ""
                                newNote = ""
                                newTime = "12:00"
                                await loadReminders()
                            }
                        }
                    }
                    .frame(minWidth: 60, minHeight: 60)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Data Sharing Agreement

    private var dataSharingAgreementSheet: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "person.2.badge.key")
                            .font(.system(size: 48))
                            .foregroundColor(.white)
                            .padding(.top, 16)

                        Text("Caregiver Data Sharing Agreement")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        VStack(alignment: .leading, spacing: 12) {
                            agreementItem("You are viewing wellness information shared by a member who has chosen to grant you access.")
                            agreementItem("This information is shared for personal caregiving purposes only.")
                            agreementItem("Do not share, distribute, or disclose this information to third parties without the member's explicit consent.")
                            agreementItem("The member may revoke your access at any time.")
                            agreementItem("This data is not a substitute for professional medical advice.")
                        }
                        .padding(.horizontal)

                        Button {
                            dataSharingAgreed = true
                            showingDataSharingAgreement = false
                        } label: {
                            Text("I Agree")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(theme.primary)
                                .cornerRadius(30)
                        }
                        .padding(.horizontal)
                        .accessibilityLabel("I agree to the caregiver data sharing terms")
                    }
                    .padding(.vertical, 20)
                }
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Decline") {
                        showingDataSharingAgreement = false
                    }
                    .frame(minWidth: 60, minHeight: 60)
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private func agreementItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(.white)
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }

    // MARK: - Helpers

    private func loadReminders() async {
        isLoading = true
        reminders = await caregiverService.fetchMemberReminders(memberId: member.memberId)
        isLoading = false
    }

    private func infoRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(theme.primary)
                .frame(width: 32)

            Text(label)
                .font(.body.weight(.medium))
                .foregroundColor(theme.text)

            Spacer()

            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 48)
    }

    private func timeFromString(_ time: String) -> Date {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func timeToString(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}
