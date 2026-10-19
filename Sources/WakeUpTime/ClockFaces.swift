import SwiftUI

/// Full-screen clock styles, matching the list in the original Clocks preferences.
enum ClockStyle: String, CaseIterable, Identifiable {
    case digital, digitalRed, wallClock, wallClockDark, modern, modernColors, modernLight, modernDark, circle, digits, simple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .digital: return "Digital"
        case .digitalRed: return "Digital Red"
        case .wallClock: return "Wall Clock"
        case .wallClockDark: return "Wall Clock Dark"
        case .modern: return "Modern"
        case .modernColors: return "Modern Colors"
        case .modernLight: return "Modern Light"
        case .modernDark: return "Modern Dark"
        case .circle: return "Circle Clock"
        case .digits: return "Digits"
        case .simple: return "Simple"
        }
    }

    /// Whether the info bar should use dark text.
    var isLight: Bool { self == .wallClock || self == .modernLight }
}

struct ClockFace: View {
    let style: ClockStyle
    let date: Date
    let use24Hour: Bool
    let colonVisible: Bool

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                background
                face(size)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .digital, .digitalRed, .digits, .simple:
            Color.black
        case .wallClock:
            LinearGradient(colors: [Color(white: 0.92), Color(white: 0.78)], startPoint: .top, endPoint: .bottom)
        case .wallClockDark:
            Color(red: 0.14, green: 0.15, blue: 0.16)
        case .modern:
            LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.24), Color(red: 0.05, green: 0.06, blue: 0.1)],
                           startPoint: .top, endPoint: .bottom)
        case .modernColors:
            LinearGradient(colors: [Color(red: 0.25, green: 0.1, blue: 0.4), Color(red: 0.05, green: 0.15, blue: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .modernLight:
            Color(white: 0.96)
        case .modernDark, .circle:
            Color(white: 0.07)
        }
    }

    @ViewBuilder private func face(_ size: CGSize) -> some View {
        let side = min(size.width, size.height)
        switch style {
        case .digital:
            SevenSegmentClock(date: date, use24Hour: use24Hour, colonVisible: colonVisible,
                              digitHeight: min(size.height * 0.4, size.width * 0.15))
        case .digitalRed:
            SevenSegmentClock(date: date, use24Hour: use24Hour, colonVisible: colonVisible,
                              lit: Color(red: 1, green: 0.18, blue: 0.12),
                              ghost: Color(red: 1, green: 0.1, blue: 0.1).opacity(0.06),
                              digitHeight: min(size.height * 0.4, size.width * 0.15))
        case .wallClock:
            WallClock(date: date, dark: false).frame(width: side * 0.85, height: side * 0.85)
        case .wallClockDark:
            WallClock(date: date, dark: true).frame(width: side * 0.85, height: side * 0.85)
        case .modern:
            ModernClock(date: date, face: Color(white: 0.92), marks: Color(white: 0.6), hands: Color(white: 0.15),
                        minuteHand: Color(white: 0.15), second: .orange)
                .frame(width: side * 0.75, height: side * 0.75)
        case .modernColors:
            ModernClock(date: date, face: .white.opacity(0.08), marks: .white.opacity(0.6), hands: .orange,
                        minuteHand: Color(red: 0.2, green: 0.85, blue: 0.8), second: .pink)
                .frame(width: side * 0.75, height: side * 0.75)
        case .modernLight:
            ModernClock(date: date, face: .white, marks: Color(white: 0.75), hands: Color(white: 0.2),
                        minuteHand: Color(white: 0.2), second: .red)
                .frame(width: side * 0.75, height: side * 0.75)
                .shadow(color: .black.opacity(0.15), radius: side * 0.03, y: side * 0.01)
        case .modernDark:
            ModernClock(date: date, face: Color(white: 0.12), marks: Color(white: 0.4), hands: Color(white: 0.9),
                        minuteHand: Color(white: 0.9), second: .orange)
                .frame(width: side * 0.75, height: side * 0.75)
        case .circle:
            CircleClock(date: date, use24Hour: use24Hour).frame(width: side * 0.8, height: side * 0.8)
        case .digits:
            DigitsClock(date: date, use24Hour: use24Hour, height: size.height)
        case .simple:
            SimpleClock(date: date, use24Hour: use24Hour, colonVisible: colonVisible, width: size.width)
        }
    }
}

// MARK: - Shared geometry

private struct ClockAngles {
    let hour: Double, minute: Double, second: Double

    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let h = Double(c.hour ?? 0), m = Double(c.minute ?? 0), s = Double(c.second ?? 0)
        hour = ((h.truncatingRemainder(dividingBy: 12)) + m / 60) / 12 * 2 * .pi
        minute = (m + s / 60) / 60 * 2 * .pi
        second = s / 60 * 2 * .pi
    }
}

private func point(_ center: CGPoint, _ angle: Double, _ distance: CGFloat) -> CGPoint {
    CGPoint(x: center.x + CGFloat(sin(angle)) * distance, y: center.y - CGFloat(cos(angle)) * distance)
}

/// A hand pointing up from `center`, rotated clockwise by `angle`.
private func handPath(center: CGPoint, angle: Double, length: CGFloat, tail: CGFloat, width: CGFloat) -> Path {
    Path(roundedRect: CGRect(x: -width / 2, y: -length, width: width, height: length + tail), cornerRadius: width / 2)
        .applying(CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle))
}

// MARK: - Faces

struct WallClock: View {
    let date: Date
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let a = ClockAngles(date)
            let outer = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)

            // Metal bezel
            ctx.fill(Path(ellipseIn: outer),
                     with: .linearGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.45), Color(white: 0.9)]),
                                           startPoint: CGPoint(x: outer.minX, y: outer.minY),
                                           endPoint: CGPoint(x: outer.maxX, y: outer.maxY)))
            let fr = r * 0.92
            let faceRect = CGRect(x: c.x - fr, y: c.y - fr, width: 2 * fr, height: 2 * fr)
            ctx.fill(Path(ellipseIn: faceRect), with: .color(dark ? Color(white: 0.17) : Color(white: 0.98)))
            if dark {
                // Diagonal sheen
                var sheen = Path()
                sheen.move(to: point(c, -0.35, fr))
                sheen.addLine(to: point(c, 2.4, fr))
                sheen.addArc(center: c, radius: fr, startAngle: .radians(2.4 - .pi / 2), endAngle: .radians(-0.35 - .pi / 2), clockwise: true)
                ctx.fill(sheen, with: .color(.white.opacity(0.05)))
            }

            let ink = dark ? Color(white: 0.85) : Color(white: 0.15)
            for i in 0..<60 {
                let angle = Double(i) / 60 * 2 * .pi
                let major = i % 5 == 0
                var p = Path()
                p.move(to: point(c, angle, fr * 0.94))
                p.addLine(to: point(c, angle, fr * (major ? 0.8 : 0.89)))
                ctx.stroke(p, with: .color(ink.opacity(major ? 1 : 0.6)), lineWidth: major ? r * 0.018 : r * 0.006)
            }

            // Day badge
            let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "en_US"))).uppercased()
            let badgeCenter = CGPoint(x: c.x - fr * 0.5, y: c.y)
            let badge = CGRect(x: badgeCenter.x - r * 0.1, y: badgeCenter.y - r * 0.055, width: r * 0.2, height: r * 0.11)
            ctx.fill(Path(roundedRect: badge, cornerRadius: r * 0.015), with: .color(Color(white: 0.92)))
            ctx.stroke(Path(roundedRect: badge, cornerRadius: r * 0.015), with: .color(Color(white: 0.5)), lineWidth: 1)
            ctx.draw(Text(weekday).font(.system(size: r * 0.06, weight: .medium)).foregroundColor(Color(white: 0.35)),
                     at: badgeCenter)

            // Seconds sub-dial
            let sc = CGPoint(x: c.x, y: c.y + fr * 0.45)
            let sr = fr * 0.2
            ctx.fill(Path(ellipseIn: CGRect(x: sc.x - sr, y: sc.y - sr, width: 2 * sr, height: 2 * sr)),
                     with: .color(dark ? Color(white: 0.12) : Color(white: 0.92)))
            for i in 0..<12 {
                let angle = Double(i) / 12 * 2 * .pi
                var p = Path()
                p.move(to: point(sc, angle, sr * 0.92))
                p.addLine(to: point(sc, angle, sr * 0.75))
                ctx.stroke(p, with: .color(ink.opacity(0.6)), lineWidth: r * 0.006)
            }
            ctx.fill(handPath(center: sc, angle: a.second, length: sr * 0.85, tail: sr * 0.15, width: r * 0.01),
                     with: .color(ink))

            // Hands
            let handColor = dark ? Color(white: 0.92) : Color(white: 0.12)
            ctx.fill(handPath(center: c, angle: a.hour, length: fr * 0.5, tail: fr * 0.08, width: r * 0.035),
                     with: .color(handColor))
            ctx.fill(handPath(center: c, angle: a.minute, length: fr * 0.78, tail: fr * 0.08, width: r * 0.022),
                     with: .color(handColor))
            let cap = r * 0.035
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - cap, y: c.y - cap, width: 2 * cap, height: 2 * cap)),
                     with: .color(Color(white: 0.6)))
        }
    }
}

struct ModernClock: View {
    let date: Date
    let face: Color
    let marks: Color
    let hands: Color
    let minuteHand: Color
    let second: Color

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let a = ClockAngles(date)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(face))
            for i in 0..<12 {
                let p = point(c, Double(i) / 12 * 2 * .pi, r * 0.86)
                let d = i % 3 == 0 ? r * 0.05 : r * 0.028
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)), with: .color(marks))
            }
            ctx.fill(handPath(center: c, angle: a.hour, length: r * 0.5, tail: 0, width: r * 0.07), with: .color(hands))
            ctx.fill(handPath(center: c, angle: a.minute, length: r * 0.75, tail: 0, width: r * 0.045), with: .color(minuteHand))
            ctx.fill(handPath(center: c, angle: a.second, length: r * 0.82, tail: r * 0.15, width: r * 0.012), with: .color(second))
            let cap = r * 0.04
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - cap, y: c.y - cap, width: 2 * cap, height: 2 * cap)), with: .color(second))
        }
    }
}

struct CircleClock: View {
    let date: Date
    let use24Hour: Bool

    var body: some View {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let h = Double((c.hour ?? 0) % 12) + Double(c.minute ?? 0) / 60
        let m = Double(c.minute ?? 0) + Double(c.second ?? 0) / 60
        let s = Double(c.second ?? 0)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = side * 0.045
            ZStack {
                ring(fraction: h / 12, color: Color(red: 1, green: 0.35, blue: 0.4), inset: 0, line: line)
                ring(fraction: m / 60, color: Color(red: 0.6, green: 1, blue: 0.3), inset: line * 1.4, line: line)
                ring(fraction: s / 60, color: Color(red: 0.25, green: 0.85, blue: 1), inset: line * 2.8, line: line)
                VStack(spacing: side * 0.01) {
                    Text(TimeFormat.time(date, use24Hour: use24Hour))
                        .font(.system(size: side * 0.13, weight: .thin, design: .rounded))
                        .monospacedDigit()
                    Text(TimeFormat.shortDate(date).uppercased())
                        .font(.system(size: side * 0.035, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ring(fraction: Double, color: Color, inset: CGFloat, line: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset + line / 2)
    }
}

struct DigitsClock: View {
    let date: Date
    let use24Hour: Bool
    let height: CGFloat

    var body: some View {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let h24 = c.hour ?? 0
        let hour = use24Hour ? h24 : (h24 % 12 == 0 ? 12 : h24 % 12)
        VStack(spacing: -height * 0.06) {
            Text(String(format: "%02d", hour))
                .foregroundStyle(Color(white: 0.92))
            Text(String(format: "%02d", c.minute ?? 0))
                .foregroundStyle(Color(white: 0.55))
        }
        .font(.system(size: height * 0.38, weight: .heavy, design: .rounded))
        .monospacedDigit()
        .overlay(alignment: .bottomTrailing) {
            Text(String(format: "%02d", c.second ?? 0))
                .font(.system(size: height * 0.06, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
                .offset(x: height * 0.08)
        }
    }
}

struct SimpleClock: View {
    let date: Date
    let use24Hour: Bool
    let colonVisible: Bool
    let width: CGFloat

    var body: some View {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h24 = c.hour ?? 0
        let hour = use24Hour ? String(format: "%02d", h24) : String(h24 % 12 == 0 ? 12 : h24 % 12)
        VStack(spacing: width * 0.01) {
            HStack(spacing: 0) {
                Text(hour)
                Text(":").opacity(colonVisible ? 1 : 0.2)
                Text(String(format: "%02d", c.minute ?? 0))
                if !use24Hour {
                    Text(h24 < 12 ? " AM" : " PM").font(.system(size: width * 0.04, weight: .light))
                }
            }
            .font(.system(size: width * 0.18, weight: .ultraLight))
            .monospacedDigit()
            Text(TimeFormat.longDate(date))
                .font(.system(size: width * 0.025, weight: .light))
                .foregroundStyle(Color(white: 0.6))
        }
        .foregroundStyle(.white)
    }
}
