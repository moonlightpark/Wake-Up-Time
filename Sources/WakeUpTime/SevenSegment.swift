import SwiftUI

/// One LCD digit. Unlit segments are drawn faintly, like a real LCD.
struct SevenSegmentDigit: View {
    enum Segment: CaseIterable { case a, b, c, d, e, f, g }

    let digit: Int?
    let lit: Color
    let ghost: Color

    private static let map: [Int: Set<Segment>] = [
        0: [.a, .b, .c, .d, .e, .f], 1: [.b, .c], 2: [.a, .b, .g, .e, .d],
        3: [.a, .b, .g, .c, .d], 4: [.f, .g, .b, .c], 5: [.a, .f, .g, .c, .d],
        6: [.a, .f, .g, .e, .c, .d], 7: [.a, .b, .c], 8: Set(Segment.allCases),
        9: [.a, .b, .c, .d, .f, .g],
    ]

    var body: some View {
        let on = digit.flatMap { Self.map[$0] } ?? []
        ZStack {
            Canvas { ctx, size in
                for seg in Segment.allCases where !on.contains(seg) {
                    ctx.fill(Self.path(seg, in: size), with: .color(ghost))
                }
            }
            Canvas { ctx, size in
                for seg in on {
                    ctx.fill(Self.path(seg, in: size), with: .color(lit))
                }
            }
            .shadow(color: lit.opacity(0.55), radius: 5)
        }
    }

    static func path(_ seg: Segment, in size: CGSize) -> Path {
        let w = size.width, h = size.height
        let t = w * 0.2
        let gap = t * 0.14
        func horizontal(_ y: CGFloat) -> Path {
            let x0 = t / 2 + gap, x1 = w - t / 2 - gap
            return Path { p in
                p.move(to: CGPoint(x: x0, y: y))
                p.addLine(to: CGPoint(x: x0 + t / 2, y: y - t / 2))
                p.addLine(to: CGPoint(x: x1 - t / 2, y: y - t / 2))
                p.addLine(to: CGPoint(x: x1, y: y))
                p.addLine(to: CGPoint(x: x1 - t / 2, y: y + t / 2))
                p.addLine(to: CGPoint(x: x0 + t / 2, y: y + t / 2))
                p.closeSubpath()
            }
        }
        func vertical(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
            let a = y0 + gap, b = y1 - gap
            return Path { p in
                p.move(to: CGPoint(x: x, y: a))
                p.addLine(to: CGPoint(x: x + t / 2, y: a + t / 2))
                p.addLine(to: CGPoint(x: x + t / 2, y: b - t / 2))
                p.addLine(to: CGPoint(x: x, y: b))
                p.addLine(to: CGPoint(x: x - t / 2, y: b - t / 2))
                p.addLine(to: CGPoint(x: x - t / 2, y: a + t / 2))
                p.closeSubpath()
            }
        }
        switch seg {
        case .a: return horizontal(t / 2)
        case .g: return horizontal(h / 2)
        case .d: return horizontal(h - t / 2)
        case .f: return vertical(t / 2, t / 2, h / 2)
        case .b: return vertical(w - t / 2, t / 2, h / 2)
        case .e: return vertical(t / 2, h / 2, h - t / 2)
        case .c: return vertical(w - t / 2, h / 2, h - t / 2)
        }
    }
}

/// The LCD clock: day-of-week row above "88:88" digits with an AM/PM indicator.
struct SevenSegmentClock: View {
    let date: Date
    let use24Hour: Bool
    let colonVisible: Bool
    var lit = Color(red: 0.80, green: 0.87, blue: 1.0)
    var ghost = Color(red: 0.55, green: 0.65, blue: 0.9).opacity(0.07)
    var digitHeight: CGFloat = 80
    var showsDays = true

    private static let days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    var body: some View {
        let cal = Calendar.current
        let hour24 = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let weekday = cal.component(.weekday, from: date) - 1
        let hour = use24Hour ? hour24 : (hour24 % 12 == 0 ? 12 : hour24 % 12)
        let hourTens: Int? = use24Hour ? hour / 10 : (hour >= 10 ? 1 : nil)
        let digitWidth = digitHeight * 0.56
        let spacing = digitHeight * 0.13

        VStack(spacing: digitHeight * 0.14) {
            if showsDays {
                HStack(spacing: digitHeight * 0.18) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(Self.days[i])
                            .foregroundStyle(i == weekday ? lit : lit.opacity(0.13))
                            .shadow(color: i == weekday ? lit.opacity(0.6) : .clear, radius: 3)
                    }
                }
                .font(.system(size: digitHeight * 0.14, weight: .bold, design: .rounded))
            }
            HStack(spacing: spacing) {
                SevenSegmentDigit(digit: hourTens, lit: lit, ghost: ghost)
                    .frame(width: digitWidth, height: digitHeight)
                SevenSegmentDigit(digit: hour % 10, lit: lit, ghost: ghost)
                    .frame(width: digitWidth, height: digitHeight)
                colon
                SevenSegmentDigit(digit: minute / 10, lit: lit, ghost: ghost)
                    .frame(width: digitWidth, height: digitHeight)
                SevenSegmentDigit(digit: minute % 10, lit: lit, ghost: ghost)
                    .frame(width: digitWidth, height: digitHeight)
                meridiem(isPM: hour24 >= 12)
                    .frame(width: digitHeight * 0.3)
                    .opacity(use24Hour ? 0 : 1)
            }
            .padding(.leading, digitHeight * 0.3 + spacing)
        }
    }

    private var colon: some View {
        let dot = digitHeight * 0.11
        return VStack(spacing: digitHeight * 0.28) {
            Circle().frame(width: dot, height: dot)
            Circle().frame(width: dot, height: dot)
        }
        .foregroundStyle(colonVisible ? lit : ghost)
        .shadow(color: colonVisible ? lit.opacity(0.55) : .clear, radius: 4)
        .padding(.horizontal, digitHeight * 0.05)
    }

    private func meridiem(isPM: Bool) -> some View {
        VStack(spacing: digitHeight * 0.06) {
            Text("AM").foregroundStyle(isPM ? lit.opacity(0.13) : lit)
            Text("PM").foregroundStyle(isPM ? lit : lit.opacity(0.13))
        }
        .font(.system(size: digitHeight * 0.13, weight: .bold, design: .rounded))
    }
}
