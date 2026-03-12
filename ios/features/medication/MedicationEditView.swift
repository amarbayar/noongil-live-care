import SwiftUI

/// Add/edit form for a medication. Large touch targets, simple fields.
struct MedicationEditView: View {
    @EnvironmentObject var medicationService: MedicationService
    @EnvironmentObject var theme: ThemeService
    @Environment(\.dismiss) private var dismiss

    let medication: Medication?

    @State private var name: String = ""
    @State private var dosage: String = ""
    @State private var form: String = "pill"
    @State private var scheduleTimes: [Date] = []
    @State private var reminderEnabled: Bool = true
    @State private var isSaving = false

    private let forms = ["pill", "injection", "patch"]

    var isEditing: Bool { medication != nil }

    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    nameSection
                    dosageSection
                    formSection
                    scheduleSection
                    reminderSection
                }
                .scrollContentBackground(.hidden)
                .foregroundColor(theme.text)
            }
            .screenBackground()
            .navigationTitle(isEditing ? "Edit Medication" : "Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .frame(minWidth: 60, minHeight: 60)
                        .tint(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .frame(minWidth: 60, minHeight: 60)
                    .tint(.white)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("Medication name", text: $name)
                .font(.body)
                .frame(minHeight: 44)
                .accessibilityLabel("Medication name")
        }
        .listRowBackground(GlassCard.listRowBackground())
    }

    private var dosageSection: some View {
        Section("Dosage") {
            TextField("e.g. 100mg", text: $dosage)
                .font(.body)
                .frame(minHeight: 44)
                .accessibilityLabel("Dosage")
        }
        .listRowBackground(GlassCard.listRowBackground())
    }

    private var formSection: some View {
        Section("Form") {
            Picker("Form", selection: $form) {
                ForEach(forms, id: \.self) { f in
                    Label(f.capitalized, systemImage: iconFor(f))
                        .tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
        }
        .listRowBackground(GlassCard.listRowBackground())
    }

    private var scheduleSection: some View {
        Section {
            ForEach(scheduleTimes.indices, id: \.self) { index in
                DatePicker(
                    "Time \(index + 1)",
                    selection: $scheduleTimes[index],
                    displayedComponents: .hourAndMinute
                )
                .frame(minHeight: 44)
                .tint(theme.primary)
            }
            .onDelete { indexSet in
                scheduleTimes.remove(atOffsets: indexSet)
            }

            Button {
                let calendar = Calendar.current
                let defaultTime = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
                scheduleTimes.append(defaultTime)
            } label: {
                Label("Add Time", systemImage: "plus.circle")
                    .foregroundColor(theme.primary)
                    .frame(minHeight: 44)
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("Set the times you need to take this medication each day.")
        }
        .listRowBackground(GlassCard.listRowBackground())
    }

    private var reminderSection: some View {
        Section {
            Toggle(isOn: $reminderEnabled) {
                Label("Reminders", systemImage: "bell")
            }
            .tint(theme.primary)
            .frame(minHeight: 44)
        } footer: {
            Text("Get a notification at each scheduled time.")
        }
        .listRowBackground(GlassCard.listRowBackground())
    }

    // MARK: - Load Existing

    private func loadExisting() {
        guard let med = medication else { return }
        name = med.name
        dosage = med.dosage ?? ""
        form = med.form ?? "pill"
        reminderEnabled = med.reminderEnabled

        let calendar = Calendar.current
        let today = Date()
        scheduleTimes = med.schedule.compactMap { timeString in
            let parts = timeString.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today)
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let schedule = scheduleTimes.map { date in
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            return String(format: "%02d:%02d", hour, minute)
        }

        if var existing = medication {
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.dosage = dosage.isEmpty ? nil : dosage.trimmingCharacters(in: .whitespaces)
            existing.form = form
            existing.schedule = schedule
            existing.reminderEnabled = reminderEnabled
            await medicationService.updateMedication(existing)
        } else {
            await medicationService.addMedication(
                name: name.trimmingCharacters(in: .whitespaces),
                dosage: dosage.isEmpty ? nil : dosage.trimmingCharacters(in: .whitespaces),
                form: form,
                schedule: schedule,
                reminderEnabled: reminderEnabled
            )
        }

        if reminderEnabled, let notif = medicationService.notificationService {
            await notif.requestPermission()
        }

        dismiss()
    }

    // MARK: - Helpers

    private func iconFor(_ form: String) -> String {
        switch form {
        case "pill": return "pills.fill"
        case "injection": return "syringe.fill"
        case "patch": return "bandage.fill"
        default: return "pills"
        }
    }
}
