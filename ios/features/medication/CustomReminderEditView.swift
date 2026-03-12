import SwiftUI

/// Edit/create form for a custom reminder.
struct CustomReminderEditView: View {
    @EnvironmentObject var customReminderService: CustomReminderService
    @EnvironmentObject var theme: ThemeService
    @Environment(\.dismiss) private var dismiss

    let existing: CustomReminder?

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var schedule: [String] = ["09:00"]
    @State private var isEnabled: Bool = true

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        titleField
                        noteField
                        scheduleSection
                        enabledToggle
                    }
                    .padding(20)
                }
            }
            .screenBackground()
            .navigationTitle(existing == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .frame(minWidth: 60, minHeight: 60)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .frame(minWidth: 60, minHeight: 60)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.text)

            TextField("e.g. Take a walk", text: $title)
                .font(.body)
                .padding(12)
                .background(theme.surface)
                .cornerRadius(10)
                .frame(minHeight: 48)
        }
        .glassCard()
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note (optional)")
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.text)

            TextField("Additional details", text: $note)
                .font(.body)
                .padding(12)
                .background(theme.surface)
                .cornerRadius(10)
                .frame(minHeight: 48)
        }
        .glassCard()
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Schedule")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.text)

                Spacer()

                Button {
                    schedule.append("12:00")
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .frame(minWidth: 60, minHeight: 60)
                }
                .tint(theme.primary)
                .accessibilityLabel("Add time slot")
            }

            ForEach(schedule.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { timeFromString(schedule[index]) },
                            set: { schedule[index] = timeToString($0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .frame(minHeight: 48)

                    if schedule.count > 1 {
                        Button {
                            schedule.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(theme.error)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Remove this time")
                    }
                }
            }
        }
        .glassCard()
    }

    private var enabledToggle: some View {
        Toggle("Enabled", isOn: $isEnabled)
            .font(.body)
            .foregroundColor(theme.text)
            .tint(theme.primary)
            .frame(minHeight: 60)
            .glassCard()
    }

    // MARK: - Actions

    private func loadExisting() {
        guard let r = existing else { return }
        title = r.title
        note = r.note ?? ""
        schedule = r.schedule.isEmpty ? ["09:00"] : r.schedule
        isEnabled = r.isEnabled
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        Task {
            if var r = existing {
                r.title = trimmedTitle
                r.note = note.isEmpty ? nil : note
                r.schedule = schedule
                r.isEnabled = isEnabled
                await customReminderService.updateReminder(r)
            } else {
                let r = CustomReminder(
                    userId: customReminderService.userId,
                    title: trimmedTitle,
                    note: note.isEmpty ? nil : note,
                    schedule: schedule,
                    isEnabled: isEnabled,
                    createdBy: ReminderCreator(
                        userId: customReminderService.userId,
                        name: nil,
                        role: .selfUser
                    )
                )
                await customReminderService.addReminder(r)
            }
            dismiss()
        }
    }

    // MARK: - Time Helpers

    private func timeFromString(_ time: String) -> Date {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func timeToString(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}
