import SwiftUI

struct OrbView: View {
    let state: OrbState
    let size: CGFloat
    var audioLevel: Float = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rotationModel = OrbRotationModel(duration: 8.0)
    @State private var glowPulseOpacity: Double = 1.0
    @State private var listeningHaloScale: CGFloat = 1.0
    @State private var speakingPulseScale: CGFloat = 1.0
    @State private var completionFlashOpacity: Double = 0.0
    @State private var completionScale: CGFloat = 1.0

    private var style: OrbVisualStyle {
        OrbVisualStyle.make(for: state, timeOfDay: OrbTimeOfDay.current)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 12.0 : 1.0 / 60.0)) { timeline in
            let rotationDegrees = rotationModel.degrees(
                at: timeline.date.timeIntervalSinceReferenceDate,
                reduceMotion: reduceMotion
            )

            ZStack {
                outerGlow

                if state == .listening {
                    listeningHalo
                }

                orbBody(rotationDegrees: rotationDegrees)

                if state == .complete {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: size, height: size)
                        .opacity(completionFlashOpacity)
                        .blendMode(.screen)
                }
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(baseScale)
        .animation(.easeInOut(duration: 0.6), value: state)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            configureStateAnimations(for: state)
            let now = Date().timeIntervalSinceReferenceDate
            rotationModel = OrbRotationModel(
                anchorDegrees: reduceMotion ? 18.0 : 0.0,
                anchorTime: now,
                duration: style.rotationDuration
            )
        }
        .onChange(of: state) { newState in
            configureStateAnimations(for: newState)
            let now = Date().timeIntervalSinceReferenceDate
            let newDuration = OrbVisualStyle.make(for: newState, timeOfDay: OrbTimeOfDay.current).rotationDuration
            rotationModel.transition(toDuration: newDuration, at: now, reduceMotion: reduceMotion)
        }
    }

    private var baseScale: CGFloat {
        CGFloat(style.orbScale) * speakingPulseScale * completionScale
    }

    private var outerGlow: some View {
        let opacityBoost = state == .listening ? Double(audioLevel) * 0.28 : 0.0
        let glowOpacity = style.glowOpacity * glowPulseOpacity + opacityBoost
        let glowScale: CGFloat = state == .processing ? 1.46 : 1.34

        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        style.glow.color.opacity(glowOpacity),
                        style.glow.color.opacity(glowOpacity * 0.35),
                        style.glow.color.opacity(0)
                    ],
                    center: .center,
                    startRadius: size * 0.08,
                    endRadius: size * 0.78
                )
            )
            .frame(width: size * glowScale, height: size * glowScale)
            .blur(radius: size * 0.03)
    }

    private var listeningHalo: some View {
        Circle()
            .stroke(style.glow.color.opacity(0.18), lineWidth: size * 0.018)
            .frame(width: size * 1.08, height: size * 1.08)
            .scaleEffect(listeningHaloScale)
            .blur(radius: size * 0.012)
            .overlay(
                Circle()
                    .stroke(style.glow.color.opacity(0.10), lineWidth: size * 0.010)
                    .scaleEffect(listeningHaloScale * CGFloat(style.listeningHaloScale / 1.08))
                    .blur(radius: size * 0.018)
            )
    }

    private func orbBody(rotationDegrees: Double) -> some View {
        return ZStack {
            Circle()
                .fill(style.baseFill.color)

            rotatingCore(rotationDegrees: rotationDegrees)
                .mask(Circle())
                .compositingGroup()
                .drawingGroup(opaque: false, colorMode: .linear)

            stationaryGlassShell
        }
        .frame(width: size, height: size)
        .shadow(
            color: Color.black.opacity(style.shellShadowOpacity),
            radius: size * 0.15,
            x: 0,
            y: size * 0.07
        )
        .shadow(
            color: style.glow.color.opacity(style.glowOpacity * 0.5),
            radius: size * 0.16,
            x: 0,
            y: size * 0.03
        )
    }

    private func rotatingCore(rotationDegrees: Double) -> some View {
        let radialStops = style.coreGradient.enumerated().map { index, tone in
            Gradient.Stop(
                color: tone.color,
                location: style.coreStopLocations[index]
            )
        }

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: radialStops),
                        center: UnitPoint(x: 0.35, y: 0.45),
                        startRadius: 0,
                        endRadius: size * CGFloat(style.coreRadialEndScale)
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: radialStops),
                        center: UnitPoint(x: 0.35, y: 0.45),
                        startRadius: 0,
                        endRadius: size * CGFloat(style.coreRadialEndScale)
                    )
                )
                .blur(radius: size * 0.012)
                .opacity(style.accentOpacity)
                .blendMode(.screen)
        }
        .rotationEffect(.degrees(rotationDegrees))
    }

    private var stationaryGlassShell: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(style.shellFillOpacity),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(style.rimOpacity),
                            Color.white.opacity(style.rimOpacity * 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.6, size * 0.012)
                )

            Circle()
                .strokeBorder(Color.white.opacity(style.innerRingOpacity), lineWidth: max(1.0, size * 0.004))
                .padding(size * 0.035)
                .blur(radius: size * 0.01)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(style.upperHighlightOpacity),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.52, height: size * 0.18)
                .rotationEffect(.degrees(-18))
                .offset(x: -size * 0.10, y: -size * 0.24)
                .blur(radius: size * 0.018)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.clear,
                            style.coreGradient[3].color.opacity(style.lowerHighlightOpacity)
                        ],
                        center: UnitPoint(x: 0.72, y: 0.78),
                        startRadius: size * 0.14,
                        endRadius: size * 0.56
                    )
                )
                .blendMode(.multiply)
        }
    }

    private func configureStateAnimations(for newState: OrbState) {
        glowPulseOpacity = 1.0
        listeningHaloScale = 1.0
        speakingPulseScale = 1.0

        if newState == .checkInDue {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glowPulseOpacity = 1.35
            }
        }

        if newState == .processing && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                glowPulseOpacity = 1.5
            }
        }

        if newState == .listening && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                listeningHaloScale = CGFloat(style.listeningHaloScale)
            }
        }

        if newState == .speaking && !reduceMotion {
            withAnimation(.easeInOut(duration: style.waveDuration).repeatForever(autoreverses: true)) {
                speakingPulseScale = CGFloat(style.speakingPulseScale)
            }
        }

        if newState == .complete && !reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) {
                completionFlashOpacity = 0.55
                completionScale = 1.06
            }
            withAnimation(.easeInOut(duration: 0.45).delay(0.18)) {
                completionFlashOpacity = 0.0
                completionScale = 1.0
            }
        } else {
            completionFlashOpacity = 0.0
            completionScale = 1.0
        }
    }

    private var accessibilityText: String {
        switch state {
        case .resting:
            return "Mira is calm"
        case .listening:
            return "Mira is listening"
        case .processing:
            return "Mira is thinking"
        case .speaking:
            return "Mira is speaking"
        case .complete:
            return "Check-in complete"
        case .checkInDue:
            return "Check-in is due. Tap to start."
        case .error:
            return "Mira is having trouble connecting"
        }
    }
}

struct OrbWaveformView: View {
    let state: OrbState
    var barCount: Int = 15

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: OrbVisualStyle {
        OrbVisualStyle.make(for: state, timeOfDay: OrbTimeOfDay.current)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 8.0 : 1.0 / 24.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(barGradient(for: index))
                        .frame(width: 4, height: barHeight(for: index, time: time))
                        .opacity(barOpacity(for: index))
                }
            }
            .frame(height: max(36, CGFloat(style.wavePeakHeight + 2)))
        }
        .accessibilityHidden(true)
    }

    private func barGradient(for index: Int) -> LinearGradient {
        let opacity: Double
        switch state {
        case .resting, .complete, .checkInDue:
            opacity = 0.55
        case .listening:
            opacity = 0.85
        case .processing:
            opacity = 0.70
        case .speaking:
            opacity = 0.90
        case .error:
            opacity = 0.45
        }

        return LinearGradient(
            colors: [Color.white.opacity(opacity * 0.7), Color.white.opacity(opacity)],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        if reduceMotion {
            return CGFloat(style.waveMinHeight)
        }

        let center = Double(barCount - 1) / 2.0
        let distance = abs(Double(index) - center)
        let emphasis = max(0.18, 1.0 - (distance / max(center, 1.0)))
        let phase = Double(index) * 0.24
        let duration = style.waveDuration

        switch state {
        case .resting:
            let oscillation = (sin((time / duration) + phase) + 1.0) * 0.5
            return CGFloat(style.waveMinHeight + oscillation * 4.0 * emphasis)
        case .listening:
            let oscillation = (sin((time / duration) * 2.6 + phase) + 1.0) * 0.5
            return CGFloat(style.waveMinHeight + oscillation * (style.wavePeakHeight - style.waveMinHeight) * (0.55 + emphasis * 0.45))
        case .processing:
            let oscillation = (sin((time / duration) * 3.2 + phase) + 1.0) * 0.5
            return CGFloat(style.waveMinHeight + oscillation * (style.wavePeakHeight - style.waveMinHeight) * 0.78)
        case .speaking:
            let oscillation = index.isMultiple(of: 2)
                ? (sin((time / duration) * 2.1 + phase) + 1.0) * 0.5
                : (cos((time / duration) * 2.6 + phase) + 1.0) * 0.5
            return CGFloat(style.waveMinHeight + oscillation * (style.wavePeakHeight - style.waveMinHeight) * (0.62 + emphasis * 0.38))
        case .complete:
            let oscillation = (sin((time / duration) + phase) + 1.0) * 0.5
            return CGFloat(style.waveMinHeight + oscillation * 5.0)
        case .checkInDue:
            let oscillation = (sin((time / duration) * 1.5 + phase) + 1.0) * 0.5
            return CGFloat(style.waveMinHeight + oscillation * 6.0)
        case .error:
            return index.isMultiple(of: 2) ? 12 : 6
        }
    }

    private func barOpacity(for index: Int) -> Double {
        let center = Double(barCount - 1) / 2.0
        let distance = abs(Double(index) - center)
        return max(0.34, 1.0 - distance * 0.06)
    }
}
