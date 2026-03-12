import SwiftUI

/// Voice-guided first-time setup flow. Large touch targets, no typing required.
struct OnboardingView: View {
    @EnvironmentObject var theme: ThemeService
    @StateObject private var onboarding = OnboardingService()

    let onComplete: (OnboardingService) -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: onboarding.progress)
                    .tint(.white)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .opacity(onboarding.currentStep == .welcome ? 0 : 1)

                Spacer()

                // Step content
                Group {
                    switch onboarding.currentStep {
                    case .welcome:
                        welcomeStep
                    case .name:
                        nameStep
                    case .condition:
                        conditionStep
                    case .speechAssessment:
                        speechAssessmentStep
                    case .checkInSchedule:
                        scheduleStep
                    case .complete:
                        completeStep
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Navigation buttons

                if onboarding.currentStep != .welcome && onboarding.currentStep != .complete {
                    navigationButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
            }
        }
        .screenBackground()
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 32) {
            OrbView(state: .resting, size: 160)

            Text("Welcome")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.white)

            Text("Your personal health companion")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))

            Button {
                onboarding.advance()
            } label: {
                Text("Get Started")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .background(theme.primary)
                    .cornerRadius(30)
            }
            .accessibilityLabel("Get started with setup")
        }
    }

    // MARK: - Name

    private var nameStep: some View {
        VStack(spacing: 24) {
            Text("What's your name?")
                .font(.title.weight(.bold))
                .foregroundColor(.white)

            Text("Mira would like to know what to call you.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))

            TextField("Your name", text: $onboarding.userName)
                .font(.title2)
                .foregroundColor(theme.text)
                .multilineTextAlignment(.center)
                .padding()
                .frame(height: 60)
                .inlineGlass()
                .accessibilityLabel("Enter your name")
        }
    }

    // MARK: - Condition

    private var conditionStep: some View {
        VStack(spacing: 24) {
            Text("What brings you here?")
                .font(.title.weight(.bold))
                .foregroundColor(.white)

            Text("This helps Mira understand how to support you best.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))

            VStack(spacing: 12) {
                ForEach(UserCondition.allCases, id: \.self) { condition in
                    conditionOptionButton(condition)
                }
            }
        }
    }

    @ViewBuilder
    private func conditionOptionButton(_ condition: UserCondition) -> some View {
        let isSelected = onboarding.selectedCondition == condition
        Button {
            onboarding.selectedCondition = condition
        } label: {
            let row = HStack(spacing: 16) {
                Image(systemName: condition.icon)
                    .font(.title2)
                    .frame(width: 32)
                Text(condition.displayName)
                    .font(.title3.weight(.medium))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                }
            }
            .foregroundColor(isSelected ? .white : theme.text)
            .padding(.horizontal, 20)
            .frame(height: 60)

            if isSelected {
                row.background(theme.primary).cornerRadius(16)
            } else {
                row.inlineGlass()
            }
        }
        .accessibilityLabel(condition.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Speech Assessment

    private var speechAssessmentStep: some View {
        VStack(spacing: 24) {
            Text("How is your speech?")
                .font(.title.weight(.bold))
                .foregroundColor(.white)

            Text("This helps Mira listen more carefully when needed.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))

            VStack(spacing: 12) {
                speechOption(level: .none, title: "Clear", subtitle: "No difficulty speaking")
                speechOption(level: .mild, title: "Mild", subtitle: "Occasionally unclear")
                speechOption(level: .moderate, title: "Moderate", subtitle: "Often unclear to new listeners")
                speechOption(level: .severe, title: "Significant", subtitle: "Most people have difficulty understanding")
            }
        }
    }

    @ViewBuilder
    private func speechOption(level: SpeechAccommodationLevel, title: String, subtitle: String) -> some View {
        let isSelected = onboarding.speechAccommodation == level
        Button {
            onboarding.speechAccommodation = level
        } label: {
            let row = HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.medium))
                    Text(subtitle)
                        .font(.footnote)
                        .opacity(0.8)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                }
            }
            .foregroundColor(isSelected ? .white : theme.text)
            .padding(.horizontal, 20)
            .frame(minHeight: 60)

            if isSelected {
                row.background(theme.primary).cornerRadius(16)
            } else {
                row.inlineGlass()
            }
        }
        .accessibilityLabel("\(title): \(subtitle)")
    }

    // MARK: - Schedule

    private var scheduleStep: some View {
        VStack(spacing: 24) {
            Text("When should Mira check in?")
                .font(.title.weight(.bold))
                .foregroundColor(.white)

            Text("Pick the times that work best for you.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))

            VStack(spacing: 16) {
                scheduleToggle(
                    label: "Morning",
                    time: $onboarding.morningTime,
                    enabled: $onboarding.morningEnabled,
                    icon: "sunrise"
                )
                scheduleToggle(
                    label: "Evening",
                    time: $onboarding.eveningTime,
                    enabled: $onboarding.eveningEnabled,
                    icon: "sunset"
                )
            }
        }
    }

    private func scheduleToggle(label: String, time: Binding<String>, enabled: Binding<Bool>, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(theme.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.title3.weight(.medium))
                    .foregroundColor(theme.text)
                Text(time.wrappedValue)
                    .font(.body)
                    .foregroundColor(theme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: enabled)
                .labelsHidden()
                .tint(theme.primary)
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
        .inlineGlass()
        .accessibilityLabel("\(label) check-in at \(time.wrappedValue)")
    }

    // MARK: - Complete

    private var completeStep: some View {
        VStack(spacing: 32) {
            OrbView(state: .complete, size: 160)

            Text("You're all set!")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.white)

            if !onboarding.userName.isEmpty {
                Text("Nice to meet you, \(onboarding.userName).")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }

            Button {
                onComplete(onboarding)
            } label: {
                Text("Start Using Mira")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .background(theme.primary)
                    .cornerRadius(30)
            }
            .accessibilityLabel("Finish setup and start using the app")
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            Button {
                onboarding.goBack()
            } label: {
                Text("Back")
                    .font(.body.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .inlineGlass(cornerRadius: 30)
            }
            .accessibilityLabel("Go back")

            Button {
                onboarding.advance()
            } label: {
                Text("Next")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .background(theme.primary)
                    .cornerRadius(30)
            }
            .accessibilityLabel("Continue to next step")
        }
    }
}
