import SwiftUI

enum OrbTimeOfDay: Equatable {
    case morning
    case afternoon
    case evening
    case night

    static var current: OrbTimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<21:
            return .evening
        default:
            return .night
        }
    }
}

struct OrbTone: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var brightness: Double {
        (0.299 * red) + (0.587 * green) + (0.114 * blue)
    }
}

struct OrbVisualStyle: Equatable {
    let baseFill: OrbTone
    let coreGradient: [OrbTone]
    let accentGradient: [OrbTone]
    let glow: OrbTone
    let orbScale: Double
    let rotationDuration: Double
    let glowOpacity: Double
    let listeningHaloScale: Double
    let speakingPulseScale: Double
    let waveMinHeight: Double
    let wavePeakHeight: Double
    let waveDuration: Double
    let shellFillOpacity: Double
    let rimOpacity: Double
    let shellShadowOpacity: Double
    let upperHighlightOpacity: Double
    let lowerHighlightOpacity: Double
    let coreStopLocations: [Double]
    let coreHighlightOpacity: Double
    let coreHighlightWidthScale: Double
    let coreHighlightHeightScale: Double
    let coreRadialEndScale: Double
    let accentOpacity: Double
    let innerRingOpacity: Double

    init(
        baseFill: OrbTone,
        coreGradient: [OrbTone],
        accentGradient: [OrbTone],
        glow: OrbTone,
        orbScale: Double,
        rotationDuration: Double,
        glowOpacity: Double,
        listeningHaloScale: Double,
        speakingPulseScale: Double,
        waveMinHeight: Double,
        wavePeakHeight: Double,
        waveDuration: Double,
        shellFillOpacity: Double,
        rimOpacity: Double,
        shellShadowOpacity: Double,
        upperHighlightOpacity: Double,
        lowerHighlightOpacity: Double,
        coreStopLocations: [Double] = [0.0, 0.20, 0.55, 1.0],
        coreHighlightOpacity: Double = 0.48,
        coreHighlightWidthScale: Double = 0.26,
        coreHighlightHeightScale: Double = 0.14,
        coreRadialEndScale: Double = 0.56,
        accentOpacity: Double = 0.62,
        innerRingOpacity: Double = 0.06
    ) {
        self.baseFill = baseFill
        self.coreGradient = coreGradient
        self.accentGradient = accentGradient
        self.glow = glow
        self.orbScale = orbScale
        self.rotationDuration = rotationDuration
        self.glowOpacity = glowOpacity
        self.listeningHaloScale = listeningHaloScale
        self.speakingPulseScale = speakingPulseScale
        self.waveMinHeight = waveMinHeight
        self.wavePeakHeight = wavePeakHeight
        self.waveDuration = waveDuration
        self.shellFillOpacity = shellFillOpacity
        self.rimOpacity = rimOpacity
        self.shellShadowOpacity = shellShadowOpacity
        self.upperHighlightOpacity = upperHighlightOpacity
        self.lowerHighlightOpacity = lowerHighlightOpacity
        self.coreStopLocations = coreStopLocations
        self.coreHighlightOpacity = coreHighlightOpacity
        self.coreHighlightWidthScale = coreHighlightWidthScale
        self.coreHighlightHeightScale = coreHighlightHeightScale
        self.coreRadialEndScale = coreRadialEndScale
        self.accentOpacity = accentOpacity
        self.innerRingOpacity = innerRingOpacity
    }

    // MARK: - State → Style

    static func make(for state: OrbState, timeOfDay: OrbTimeOfDay) -> OrbVisualStyle {
        switch state {
        case .resting:
            return calmStyle(for: timeOfDay)

        // Listening — white→cyan core, bright glass, expanded
        // HTML: orb-c1 white 0.8, orb-c2 cyan(0,200,255) 0.8, scale 1.1, speed 4s
        case .listening:
            return OrbVisualStyle(
                baseFill: tone(0.13, 0.58, 0.69, 1.0),
                coreGradient: [
                    tone(1.0, 1.0, 1.0, 0.80),
                    tone(1.0, 1.0, 1.0, 0.80),
                    tone(0.0, 0.78, 1.0, 0.80),
                    tone(0.13, 0.58, 0.93, 0.80)
                ],
                accentGradient: [
                    tone(0.43, 0.84, 0.93, 0.80),
                    tone(0.0, 0.78, 1.0, 0.84),
                    tone(0.13, 0.58, 0.93, 0.80),
                    tone(0.43, 0.84, 0.93, 0.76)
                ],
                glow: tone(0.0, 0.78, 1.0, 1.0),
                orbScale: 1.10,
                rotationDuration: 5.2,
                glowOpacity: 0.38,
                listeningHaloScale: 1.16,
                speakingPulseScale: 1.0,
                waveMinHeight: 8,
                wavePeakHeight: 25,
                waveDuration: 1.0,
                shellFillOpacity: 0.20,
                rimOpacity: 0.36,
                shellShadowOpacity: 0.10,
                upperHighlightOpacity: 0.88,
                lowerHighlightOpacity: 0.24,
                coreHighlightOpacity: 0.80,
                coreRadialEndScale: 0.56
            )

        // Processing/Thinking — green→blue core, fast spin, contracted
        // HTML: orb-c1 green(0,255,150) 0.6, orb-c2 blue(0,100,255) 0.8, scale 0.95, speed 2s
        case .processing:
            return OrbVisualStyle(
                baseFill: tone(0.09, 0.15, 0.28, 1.0),
                coreGradient: [
                    tone(1.0, 1.0, 1.0, 0.60),
                    tone(0.0, 1.0, 0.59, 0.60),
                    tone(0.0, 0.39, 1.0, 0.80),
                    tone(0.09, 0.15, 0.28, 0.90)
                ],
                accentGradient: [
                    tone(0.0, 0.78, 0.59, 0.76),
                    tone(0.0, 0.39, 1.0, 0.82),
                    tone(0.0, 1.0, 0.59, 0.74),
                    tone(0.09, 0.15, 0.28, 0.80)
                ],
                glow: tone(0.0, 1.0, 0.59, 1.0),
                orbScale: 0.95,
                rotationDuration: 3.8,
                glowOpacity: 0.38,
                listeningHaloScale: 1.0,
                speakingPulseScale: 1.0,
                waveMinHeight: 4,
                wavePeakHeight: 17,
                waveDuration: 0.65,
                shellFillOpacity: 0.15,
                rimOpacity: 0.28,
                shellShadowOpacity: 0.18,
                upperHighlightOpacity: 0.82,
                lowerHighlightOpacity: 0.16,
                coreHighlightOpacity: 0.70,
                coreRadialEndScale: 0.56
            )

        // Speaking — white→hot-pink core, pulsing wrapper
        // HTML: orb-c1 white 0.9, orb-c2 pink(255,50,150) 0.8, scale 1.05, speed 4s, pulse→1.12
        case .speaking:
            return OrbVisualStyle(
                baseFill: tone(1.0, 0.46, 0.55, 1.0),
                coreGradient: [
                    tone(1.0, 1.0, 1.0, 0.90),
                    tone(1.0, 0.20, 0.59, 0.80),
                    tone(0.98, 0.30, 0.64, 0.90),
                    tone(0.56, 0.20, 0.70, 0.80)
                ],
                accentGradient: [
                    tone(1.0, 0.84, 0.90, 0.80),
                    tone(1.0, 0.50, 0.70, 0.84),
                    tone(0.98, 0.30, 0.64, 0.80),
                    tone(1.0, 0.72, 0.86, 0.76)
                ],
                glow: tone(1.0, 0.46, 0.55, 1.0),
                orbScale: 1.05,
                rotationDuration: 5.0,
                glowOpacity: 0.34,
                listeningHaloScale: 1.0,
                speakingPulseScale: 1.12,
                waveMinHeight: 12,
                wavePeakHeight: 34,
                waveDuration: 0.36,
                shellFillOpacity: 0.22,
                rimOpacity: 0.36,
                shellShadowOpacity: 0.08,
                upperHighlightOpacity: 0.88,
                lowerHighlightOpacity: 0.26,
                coreHighlightOpacity: 0.90,
                coreRadialEndScale: 0.56
            )

        case .complete:
            return OrbVisualStyle(
                baseFill: tone(0.98, 0.94, 0.96, 1.0),
                coreGradient: [
                    tone(0.98, 0.74, 0.84, 0.90),
                    tone(0.94, 0.52, 0.72, 0.92),
                    tone(0.86, 0.40, 0.68, 0.90),
                    tone(1.0, 0.96, 0.98, 0.90)
                ],
                accentGradient: [
                    tone(1.0, 0.88, 0.92, 0.78),
                    tone(0.96, 0.62, 0.78, 0.80),
                    tone(0.88, 0.46, 0.72, 0.80),
                    tone(1.0, 0.94, 0.96, 0.80)
                ],
                glow: tone(0.94, 0.56, 0.72, 1.0),
                orbScale: 1.0,
                rotationDuration: 6.5,
                glowOpacity: 0.22,
                listeningHaloScale: 1.0,
                speakingPulseScale: 1.0,
                waveMinHeight: 8,
                wavePeakHeight: 14,
                waveDuration: 1.4,
                shellFillOpacity: 0.18,
                rimOpacity: 0.30,
                shellShadowOpacity: 0.08,
                upperHighlightOpacity: 0.80,
                lowerHighlightOpacity: 0.22,
                coreHighlightOpacity: 0.72
            )

        case .checkInDue:
            return OrbVisualStyle(
                baseFill: tone(0.98, 0.95, 0.88, 1.0),
                coreGradient: [
                    tone(1.0, 0.90, 0.50, 0.90),
                    tone(0.98, 0.74, 0.28, 0.94),
                    tone(0.88, 0.52, 0.16, 0.92),
                    tone(1.0, 0.96, 0.82, 0.88)
                ],
                accentGradient: [
                    tone(1.0, 0.94, 0.72, 0.80),
                    tone(0.98, 0.80, 0.40, 0.84),
                    tone(0.92, 0.62, 0.18, 0.82),
                    tone(1.0, 0.97, 0.86, 0.80)
                ],
                glow: tone(0.96, 0.72, 0.26, 1.0),
                orbScale: 1.0,
                rotationDuration: 5.5,
                glowOpacity: 0.28,
                listeningHaloScale: 1.08,
                speakingPulseScale: 1.0,
                waveMinHeight: 7,
                wavePeakHeight: 13,
                waveDuration: 1.2,
                shellFillOpacity: 0.16,
                rimOpacity: 0.28,
                shellShadowOpacity: 0.10,
                upperHighlightOpacity: 0.78,
                lowerHighlightOpacity: 0.20,
                coreHighlightOpacity: 0.68
            )

        case .error:
            return OrbVisualStyle(
                baseFill: tone(0.22, 0.08, 0.10, 1.0),
                coreGradient: [
                    tone(0.92, 0.34, 0.34, 0.86),
                    tone(0.74, 0.16, 0.18, 0.92),
                    tone(0.52, 0.10, 0.12, 0.98),
                    tone(0.98, 0.86, 0.86, 0.72)
                ],
                accentGradient: [
                    tone(0.98, 0.68, 0.68, 0.74),
                    tone(0.88, 0.28, 0.30, 0.80),
                    tone(0.62, 0.14, 0.18, 0.82),
                    tone(0.98, 0.86, 0.86, 0.72)
                ],
                glow: tone(0.82, 0.18, 0.22, 1.0),
                orbScale: 1.0,
                rotationDuration: 5.2,
                glowOpacity: 0.24,
                listeningHaloScale: 1.0,
                speakingPulseScale: 1.0,
                waveMinHeight: 6,
                wavePeakHeight: 12,
                waveDuration: 0.9,
                shellFillOpacity: 0.10,
                rimOpacity: 0.24,
                shellShadowOpacity: 0.16,
                upperHighlightOpacity: 0.72,
                lowerHighlightOpacity: 0.14,
                coreHighlightOpacity: 0.56
            )
        }
    }

    // MARK: - Calm / Resting (time-of-day variants)
    // All variants share the HTML neutral palette: cyan + magenta + purple core
    // with subtle warm/cool shifts per time of day.

    private static func calmStyle(for timeOfDay: OrbTimeOfDay) -> OrbVisualStyle {
        switch timeOfDay {
        case .morning:
            return OrbVisualStyle(
                baseFill: tone(0.10, 0.12, 0.24, 1.0),
                coreGradient: [
                    tone(1.0, 0.96, 0.88, 0.80),
                    tone(0.0, 0.92, 0.94, 0.60),
                    tone(1.0, 0.48, 0.92, 0.60),
                    tone(0.42, 0.22, 0.96, 0.80)
                ],
                accentGradient: [
                    tone(0.0, 0.92, 0.94, 0.52),
                    tone(1.0, 0.48, 0.92, 0.56),
                    tone(0.42, 0.22, 0.96, 0.54),
                    tone(0.0, 0.78, 1.0, 0.52)
                ],
                glow: tone(0.0, 0.78, 1.0, 1.0),
                orbScale: 1.0,
                rotationDuration: 8.0,
                glowOpacity: 0.22,
                listeningHaloScale: 1.0,
                speakingPulseScale: 1.0,
                waveMinHeight: 6,
                wavePeakHeight: 11,
                waveDuration: 2.0,
                shellFillOpacity: 0.10,
                rimOpacity: 0.26,
                shellShadowOpacity: 0.10,
                upperHighlightOpacity: 0.44,
                lowerHighlightOpacity: 0.12,
                coreHighlightOpacity: 0.76,
                coreHighlightWidthScale: 0.18,
                coreHighlightHeightScale: 0.10,
                coreRadialEndScale: 0.56,
                accentOpacity: 0.16,
                innerRingOpacity: 0.04
            )

        case .afternoon:
            // Closest to the HTML neutral: pure cyan + magenta
            return OrbVisualStyle(
                baseFill: tone(0.06, 0.08, 0.20, 1.0),
                coreGradient: [
                    tone(1.0, 1.0, 1.0, 0.80),
                    tone(0.0, 1.0, 1.0, 0.60),
                    tone(1.0, 0.41, 1.0, 0.60),
                    tone(0.39, 0.20, 1.0, 0.80)
                ],
                accentGradient: [
                    tone(0.0, 1.0, 1.0, 0.52),
                    tone(1.0, 0.41, 1.0, 0.56),
                    tone(0.39, 0.20, 1.0, 0.54),
                    tone(0.0, 0.78, 1.0, 0.52)
                ],
                glow: tone(0.0, 0.78, 1.0, 1.0),
                orbScale: 1.0,
                rotationDuration: 8.0,
                glowOpacity: 0.22,
                listeningHaloScale: 1.0,
                speakingPulseScale: 1.0,
                waveMinHeight: 6,
                wavePeakHeight: 10,
                waveDuration: 2.0,
                shellFillOpacity: 0.10,
                rimOpacity: 0.26,
                shellShadowOpacity: 0.10,
                upperHighlightOpacity: 0.44,
                lowerHighlightOpacity: 0.12,
                coreHighlightOpacity: 0.76,
                coreHighlightWidthScale: 0.18,
                coreHighlightHeightScale: 0.10,
                coreRadialEndScale: 0.56,
                accentOpacity: 0.16,
                innerRingOpacity: 0.04
            )

        case .evening:
            // Warmer — more magenta/purple
            return OrbVisualStyle(
                baseFill: tone(0.08, 0.07, 0.20, 1.0),
                coreGradient: [
                    tone(1.0, 0.94, 0.96, 0.80),
                    tone(0.0, 0.88, 1.0, 0.58),
                    tone(1.0, 0.41, 0.88, 0.62),
                    tone(0.44, 0.18, 0.92, 0.82)
                ],
                accentGradient: [
                    tone(0.0, 0.88, 1.0, 0.50),
                    tone(1.0, 0.41, 0.88, 0.56),
                    tone(0.44, 0.18, 0.92, 0.54),
                    tone(0.0, 0.72, 1.0, 0.50)
                ],
                glow: tone(0.56, 0.18, 0.88, 1.0),
                orbScale: 1.0,
                rotationDuration: 8.2,
                glowOpacity: 0.24,
                listeningHaloScale: 1.0,
                speakingPulseScale: 1.0,
                waveMinHeight: 6,
                wavePeakHeight: 11,
                waveDuration: 2.0,
                shellFillOpacity: 0.10,
                rimOpacity: 0.26,
                shellShadowOpacity: 0.12,
                upperHighlightOpacity: 0.42,
                lowerHighlightOpacity: 0.12,
                coreHighlightOpacity: 0.72,
                coreHighlightWidthScale: 0.17,
                coreHighlightHeightScale: 0.10,
                coreRadialEndScale: 0.54,
                accentOpacity: 0.16,
                innerRingOpacity: 0.04
            )

        case .night:
            // Deeper, more saturated
            return OrbVisualStyle(
                baseFill: tone(0.05, 0.06, 0.16, 1.0),
                coreGradient: [
                    tone(0.86, 0.92, 1.0, 0.74),
                    tone(0.0, 0.86, 0.96, 0.64),
                    tone(0.92, 0.36, 1.0, 0.64),
                    tone(0.34, 0.16, 0.90, 0.84)
                ],
                accentGradient: [
                    tone(0.0, 0.86, 0.96, 0.58),
                    tone(0.92, 0.36, 1.0, 0.62),
                    tone(0.34, 0.16, 0.90, 0.60),
                    tone(0.0, 0.64, 1.0, 0.58)
                ],
                glow: tone(0.28, 0.26, 0.90, 1.0),
                orbScale: 1.0,
                rotationDuration: 8.8,
                glowOpacity: 0.28,
                listeningHaloScale: 1.0,
                speakingPulseScale: 1.0,
                waveMinHeight: 6,
                wavePeakHeight: 10,
                waveDuration: 2.0,
                shellFillOpacity: 0.11,
                rimOpacity: 0.28,
                shellShadowOpacity: 0.18,
                upperHighlightOpacity: 0.40,
                lowerHighlightOpacity: 0.12,
                coreHighlightOpacity: 0.64,
                coreHighlightWidthScale: 0.16,
                coreHighlightHeightScale: 0.09,
                coreRadialEndScale: 0.54,
                accentOpacity: 0.18,
                innerRingOpacity: 0.05
            )
        }
    }

    private static func tone(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) -> OrbTone {
        OrbTone(red: red, green: green, blue: blue, alpha: alpha)
    }
}
