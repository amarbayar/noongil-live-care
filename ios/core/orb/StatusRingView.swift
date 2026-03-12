import SwiftUI

/// Segmented arc around the orb showing check-in progress.
struct StatusRingView: View {
    let progress: CheckInProgress
    let size: CGFloat

    @EnvironmentObject var theme: ThemeService

    private let lineWidth: CGFloat = 3
    private let gapDegrees: Double = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<progress.total, id: \.self) { index in
                segmentArc(index: index)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-90))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: progress.completed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.completed) of \(progress.total) check-ins completed today")
    }

    private func segmentArc(index: Int) -> some View {
        let totalGap = gapDegrees * Double(progress.total)
        let segmentDegrees = (360.0 - totalGap) / Double(progress.total)
        let startAngle = Double(index) * (segmentDegrees + gapDegrees)
        let endAngle = startAngle + segmentDegrees
        let isCompleted = index < progress.completed

        return Circle()
            .trim(
                from: startAngle / 360.0,
                to: endAngle / 360.0
            )
            .stroke(
                isCompleted ? theme.success.opacity(0.55) : theme.text.opacity(0.08),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
    }
}
