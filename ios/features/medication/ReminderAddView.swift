import SwiftUI

/// Type picker sheet: "What kind of reminder?"
struct ReminderAddView: View {
    @EnvironmentObject var theme: ThemeService

    var onMedication: () -> Void
    var onCheckIn: () -> Void
    var onCustom: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 16) {
                    Text("What kind of reminder?")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.top, 8)

                    reminderOption(
                        icon: "pills.fill",
                        title: "Medication",
                        subtitle: "Track a medication with scheduled reminders"
                    ) {
                        dismiss()
                        onMedication()
                    }

                    reminderOption(
                        icon: "bell.fill",
                        title: "Check-In",
                        subtitle: "Adjust your morning or evening check-in time"
                    ) {
                        dismiss()
                        onCheckIn()
                    }

                    reminderOption(
                        icon: "star.fill",
                        title: "Custom",
                        subtitle: "A personal reminder like exercise or hydration"
                    ) {
                        dismiss()
                        onCustom()
                    }

                    Spacer()
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .frame(minWidth: 60, minHeight: 60)
                }
            }
        }
    }

    private func reminderOption(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(theme.primary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(theme.text)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 60)
        }
        .glassCard()
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
