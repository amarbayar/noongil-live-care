import SwiftUI

/// Time-of-day aware background with visible Lovable-style gradient washes.
/// Base vertical gradient (sky-to-earth) plus 3 animated pastel blobs that shift palette by time period.
struct AuroraBackgroundView: View {
    @EnvironmentObject var theme: ThemeService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            theme.background.ignoresSafeArea()
        } else if reduceMotion {
            staticBlobs
        } else {
            animatedBlobs
        }
    }

    // MARK: - Time-of-Day Colors

    private enum TimePeriod {
        case morning, afternoon, evening, night

        static var current: TimePeriod {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12:  return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            default:      return .night
            }
        }
    }

    private struct TimeColors {
        let blob1: Color
        let blob2: Color
        let blob3: Color
        let opacity1: Double
        let opacity2: Double
        let opacity3: Double
        let gradientTop: Color
        let gradientBottom: Color
    }

    private var timeColors: TimeColors {
        switch TimePeriod.current {
        case .morning:
            return TimeColors(
                blob1: Color(red: 254/255, green: 202/255, blue: 202/255),  // #FECACA peach
                blob2: Color(red: 252/255, green: 165/255, blue: 165/255),  // #FCA5A5 rose
                blob3: Color(red: 253/255, green: 230/255, blue: 138/255),  // #FDE68A golden
                opacity1: 0.25, opacity2: 0.25, opacity3: 0.20,
                gradientTop: Color(red: 248/255, green: 250/255, blue: 252/255),    // #F8FAFC
                gradientBottom: Color(red: 255/255, green: 247/255, blue: 237/255)  // #FFF7ED
            )
        case .afternoon:
            return TimeColors(
                blob1: Color(red: 147/255, green: 197/255, blue: 253/255),  // #93C5FD blue
                blob2: Color(red: 110/255, green: 231/255, blue: 183/255),  // #6EE7B7 mint
                blob3: Color(red: 186/255, green: 230/255, blue: 253/255),  // #BAE6FD sky
                opacity1: 0.25, opacity2: 0.25, opacity3: 0.20,
                gradientTop: Color(red: 248/255, green: 250/255, blue: 252/255),    // #F8FAFC
                gradientBottom: Color(red: 239/255, green: 246/255, blue: 255/255)  // #EFF6FF
            )
        case .evening:
            return TimeColors(
                blob1: Color(red: 249/255, green: 168/255, blue: 212/255),  // #F9A8D4 pink
                blob2: Color(red: 196/255, green: 181/255, blue: 253/255),  // #C4B5FD lavender
                blob3: Color(red: 253/255, green: 186/255, blue: 116/255),  // #FDBA74 coral
                opacity1: 0.25, opacity2: 0.25, opacity3: 0.20,
                gradientTop: Color(red: 248/255, green: 250/255, blue: 252/255),    // #F8FAFC
                gradientBottom: Color(red: 253/255, green: 242/255, blue: 248/255)  // #FDF2F8
            )
        case .night:
            return TimeColors(
                blob1: Color(red: 96/255, green: 165/255, blue: 250/255),   // #60A5FA blue
                blob2: Color(red: 129/255, green: 140/255, blue: 248/255),  // #818CF8 indigo
                blob3: Color(red: 94/255, green: 234/255, blue: 212/255),   // #5EEAD4 teal
                opacity1: 0.20, opacity2: 0.20, opacity3: 0.15,
                gradientTop: Color(red: 239/255, green: 246/255, blue: 255/255),    // #EFF6FF
                gradientBottom: Color(red: 238/255, green: 242/255, blue: 255/255)  // #EEF2FF
            )
        }
    }

    // MARK: - Animated

    private var animatedBlobs: some View {
        let tc = timeColors
        return TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                // Base gradient layer (sky-to-earth)
                let bgRect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(bgRect),
                    with: .linearGradient(
                        Gradient(colors: [tc.gradientTop, tc.gradientBottom]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    )
                )

                // 3 drifting pastel blobs
                drawBlob(
                    context: &context,
                    anchor: CGPoint(x: size.width * 0.2, y: size.height * 0.15),
                    time: time,
                    color: tc.blob1, blobSize: 600,
                    opacity: tc.opacity1, phaseOffset: 0
                )
                drawBlob(
                    context: &context,
                    anchor: CGPoint(x: size.width * 0.8, y: size.height * 0.85),
                    time: time,
                    color: tc.blob2, blobSize: 500,
                    opacity: tc.opacity2, phaseOffset: -7
                )
                drawBlob(
                    context: &context,
                    anchor: CGPoint(x: size.width * 0.5, y: size.height * 0.4),
                    time: time,
                    color: tc.blob3, blobSize: 400,
                    opacity: tc.opacity3, phaseOffset: -14
                )
            }
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }

    // MARK: - Static (reduce motion)

    private var staticBlobs: some View {
        let tc = timeColors
        return Canvas { context, size in
            // Base gradient layer
            let bgRect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(bgRect),
                with: .linearGradient(
                    Gradient(colors: [tc.gradientTop, tc.gradientBottom]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )

            drawStaticBlob(context: &context,
                           center: CGPoint(x: size.width * 0.2, y: size.height * 0.15),
                           color: tc.blob1, blobSize: 600, opacity: tc.opacity1)
            drawStaticBlob(context: &context,
                           center: CGPoint(x: size.width * 0.8, y: size.height * 0.85),
                           color: tc.blob2, blobSize: 500, opacity: tc.opacity2)
            drawStaticBlob(context: &context,
                           center: CGPoint(x: size.width * 0.5, y: size.height * 0.4),
                           color: tc.blob3, blobSize: 400, opacity: tc.opacity3)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    private func drawBlob(
        context: inout GraphicsContext,
        anchor: CGPoint,
        time: TimeInterval,
        color: Color,
        blobSize: CGFloat,
        opacity: Double,
        phaseOffset: Double
    ) {
        let cycle: Double = 20
        let progress = ((time + phaseOffset).truncatingRemainder(dividingBy: cycle) + cycle)
            .truncatingRemainder(dividingBy: cycle) / cycle

        let keyframes: [(dx: CGFloat, dy: CGFloat, s: CGFloat)] = [
            (0, 0, 1.0),
            (50, -30, 1.05),
            (-30, 50, 0.95),
            (-50, -20, 1.02)
        ]

        let segment = progress * 4
        let i = Int(segment) % 4
        let j = (i + 1) % 4
        let frac = CGFloat(segment - Double(Int(segment)))
        let t = frac * frac * (3 - 2 * frac)

        let dx = keyframes[i].dx + (keyframes[j].dx - keyframes[i].dx) * t
        let dy = keyframes[i].dy + (keyframes[j].dy - keyframes[i].dy) * t
        let scale = keyframes[i].s + (keyframes[j].s - keyframes[i].s) * t

        let cx = anchor.x + dx
        let cy = anchor.y + dy
        let scaledSize = blobSize * scale
        let rect = CGRect(
            x: cx - scaledSize / 2,
            y: cy - scaledSize / 2,
            width: scaledSize,
            height: scaledSize
        )

        var ctx = context
        ctx.opacity = opacity
        ctx.addFilter(.blur(radius: 80))

        let gradient = Gradient(colors: [color, color.opacity(0)])
        let shading = GraphicsContext.Shading.radialGradient(
            gradient,
            center: CGPoint(x: cx, y: cy),
            startRadius: 0,
            endRadius: scaledSize / 2
        )

        ctx.fill(Ellipse().path(in: rect), with: shading)
    }

    private func drawStaticBlob(
        context: inout GraphicsContext,
        center: CGPoint,
        color: Color,
        blobSize: CGFloat,
        opacity: Double
    ) {
        let rect = CGRect(
            x: center.x - blobSize / 2,
            y: center.y - blobSize / 2,
            width: blobSize,
            height: blobSize
        )

        var ctx = context
        ctx.opacity = opacity
        ctx.addFilter(.blur(radius: 80))

        let gradient = Gradient(colors: [color, color.opacity(0)])
        let shading = GraphicsContext.Shading.radialGradient(
            gradient,
            center: center,
            startRadius: 0,
            endRadius: blobSize / 2
        )

        ctx.fill(Ellipse().path(in: rect), with: shading)
    }
}
