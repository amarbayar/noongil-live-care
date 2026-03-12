import SwiftUI

/// 7-day history row of white shape-based dots showing recent check-in status.
struct GlowHistoryView: View {
    let days: [GlowDay]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dotSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 12) {
            ForEach(days) { day in
                dotView(for: day.status)
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(combinedLabel)
    }

    @ViewBuilder
    private func dotView(for status: DayStatus) -> some View {
        switch status {
        case .good:
            // Solid white filled circle + subtle glow
            Circle()
                .fill(Color.white)
                .shadow(color: reduceMotion ? .clear : Color.white.opacity(0.5), radius: 4)

        case .mixed:
            // White stroke + left-half white fill
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
                HalfCircleShape()
                    .fill(Color.white)
                    .clipShape(Circle())
            }

        case .concern:
            // White stroke + small center dot
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
            }

        case .missed:
            // Dim white stroke only
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
        }
    }

    private var combinedLabel: String {
        let descriptions = days.map { day -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            let dayName = formatter.string(from: day.id)
            switch day.status {
            case .good: return "\(dayName): good"
            case .mixed: return "\(dayName): mixed"
            case .concern: return "\(dayName): needs attention"
            case .missed: return "\(dayName): missed"
            }
        }
        return "Past \(days.count) days. " + descriptions.joined(separator: ". ")
    }
}

/// Clips to the left half of the bounding rect for the half-fill indicator.
private struct HalfCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height))
    }
}
