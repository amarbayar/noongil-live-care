import SwiftUI

/// Medication list view. Shows active medications with reminder toggles.
struct MedicationSetupView: View {
    @EnvironmentObject var medicationService: MedicationService
    @EnvironmentObject var featureFlags: FeatureFlagService
    @EnvironmentObject var theme: ThemeService

    @State private var showingAddSheet = false

    var body: some View {
        NavigationView {
            ZStack {
                theme.background.ignoresSafeArea()

                Group {
                    if medicationService.medications.isEmpty {
                        emptyState
                    } else {
                        medicationList
                    }
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                            .frame(minWidth: 60, minHeight: 60)
                    }
                    .tint(theme.primary)
                    .accessibilityLabel("Add medication")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                MedicationEditView(medication: nil)
                    .environmentObject(medicationService)
            }
        }
        .task {
            await medicationService.fetchMedications()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "pills")
                .font(.system(size: 60))
                .foregroundColor(theme.textSecondary)
            Text("No medications yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(theme.text)
            Text("Add your medications to get reminders at the right times.")
                .font(.body)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingAddSheet = true
            } label: {
                Label("Add Medication", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(minWidth: 200, minHeight: 60)
                    .background(theme.primary)
                    .cornerRadius(30)
            }
            .accessibilityLabel("Add medication")
            Spacer()
        }
    }

    // MARK: - Medication List

    private var medicationList: some View {
        List {
            ForEach(activeMedications) { med in
                MedicationRow(medication: med)
            }
            .onDelete { indexSet in
                Task {
                    for index in indexSet {
                        let med = activeMedications[index]
                        if let id = med.id {
                            await medicationService.deactivateMedication(id: id)
                        }
                    }
                }
            }
            .listRowBackground(GlassCard.listRowBackground())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var activeMedications: [Medication] {
        medicationService.medications.filter(\.isActive)
    }
}

// MARK: - Medication Row

private struct MedicationRow: View {
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
                    .font(.title2)
                    .foregroundColor(theme.primary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.name)
                        .font(.headline)
                        .foregroundColor(theme.text)

                    if let dosage = medication.dosage, !dosage.isEmpty {
                        Text(dosage)
                            .font(.subheadline)
                            .foregroundColor(theme.textSecondary)
                    }

                    if !medication.schedule.isEmpty {
                        Text(medication.schedule.joined(separator: ", "))
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
            }
            .padding(.vertical, 4)
            .frame(minHeight: 60)
        }
        .accessibilityLabel("\(medication.name), \(medication.dosage ?? ""), \(medication.schedule.joined(separator: " and "))")
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
