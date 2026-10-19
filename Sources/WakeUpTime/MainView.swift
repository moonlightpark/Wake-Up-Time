import AppKit
import SwiftUI

/// Fixed geometry of the main window.
enum Layout {
    static let wood: CGFloat = 18
    static let panelWidth: CGFloat = 440
    static let drawerWidth: CGFloat = 156
    static let titleHeight: CGFloat = 24
    static let lcdHeight: CGFloat = 136
    static let barHeight: CGFloat = 64
    static let switchArea: CGFloat = 64
    static let hudWidth: CGFloat = 268
    static let hudHeight: CGFloat = 48
    static let sleepArea: CGFloat = panelWidth - switchArea - hudWidth

    static let height = titleHeight + lcdHeight + barHeight
    static let closedWidth = wood * 2 + panelWidth
    static let openWidth = closedWidth + drawerWidth

    /// Top-left corner of the HUD, used to float the stop button above the snooze catcher.
    static let hudOrigin = CGPoint(x: wood + switchArea, y: titleHeight + lcdHeight + (barHeight - hudHeight) / 2)
}

struct MainView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var alarm = AlarmController.shared
    let onToggleDrawer: () -> Void
    let onFullScreen: () -> Void
    let onSleep: () -> Void

    var body: some View {
        let ringing = alarm.phase == .ringing
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                WoodStrip(showsGrip: false, onDoubleClick: nil)
                    .frame(width: Layout.wood)
                VStack(spacing: 0) {
                    TitleBar(onFullScreen: onFullScreen)
                        .frame(height: Layout.titleHeight)
                    LCDPanel()
                        .frame(height: Layout.lcdHeight)
                    BottomBar(onSleep: onSleep)
                        .frame(height: Layout.barHeight)
                }
                .frame(width: Layout.panelWidth)
                DrawerView()
                    .frame(width: Layout.drawerWidth)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
                WoodStrip(showsGrip: true, onDoubleClick: onToggleDrawer)
                    .frame(width: Layout.wood)
            }

            // While ringing, a click anywhere on the window snoozes.
            if ringing {
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { alarm.snooze() }
            }
            if ringing || alarm.phase == .snoozing {
                StopButton { alarm.stop() }
                    .offset(x: Layout.hudOrigin.x + Layout.hudWidth - 22, y: Layout.hudOrigin.y + 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: Layout.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Window chrome

/// An AppKit view that moves the window when dragged. When `onHorizontalDrag` is set it acts
/// as a drawer handle instead: a sideways drag reports its direction (true = rightwards).
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: (() -> Void)?
    var onHorizontalDrag: ((Bool) -> Void)?

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.onDoubleClick = onDoubleClick
        view.onHorizontalDrag = onHorizontalDrag
    }

    final class DragView: NSView {
        var onDoubleClick: (() -> Void)?
        var onHorizontalDrag: ((Bool) -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // Track the drag by hand: AppKit's performDrag swallows the clicks a double-click is made of.
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2, let onDoubleClick {
                onDoubleClick()
                return
            }
            guard let window else { return }
            // Global positions recorded with each event (top-left origin), so the result
            // does not depend on how fast the events are processed.
            guard let startMouse = event.cgEvent?.location else { return }
            let startOrigin = window.frame.origin
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
                guard let mouse = next.cgEvent?.location else { continue }
                let dx = mouse.x - startMouse.x, dy = startMouse.y - mouse.y
                if let onHorizontalDrag {
                    if abs(dx) > 12 {
                        onHorizontalDrag(dx > 0)
                        return
                    }
                } else {
                    window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
                }
            }
        }
    }
}

struct WoodStrip: View {
    let showsGrip: Bool
    let onDoubleClick: (() -> Void)?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.55, green: 0.24, blue: 0.05),
                                    Color(red: 0.85, green: 0.47, blue: 0.12),
                                    Color(red: 0.78, green: 0.40, blue: 0.09),
                                    Color(red: 0.52, green: 0.22, blue: 0.04)],
                           startPoint: .leading, endPoint: .trailing)
            // Wood grain
            Canvas { ctx, size in
                var seed: UInt64 = 0x9E3779B97F4A7C15
                func rand() -> CGFloat {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return CGFloat(seed >> 33) / CGFloat(1 << 31)
                }
                for _ in 0..<14 {
                    let x = rand() * size.width
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addCurve(to: CGPoint(x: x + (rand() - 0.5) * 3, y: size.height),
                               control1: CGPoint(x: x + (rand() - 0.5) * 4, y: size.height * 0.33),
                               control2: CGPoint(x: x + (rand() - 0.5) * 4, y: size.height * 0.66))
                    ctx.stroke(p, with: .color(.black.opacity(0.08 + rand() * 0.1)), lineWidth: 0.5 + rand())
                }
            }
            if showsGrip {
                HStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { _ in
                        Capsule().fill(Color.black.opacity(0.45)).frame(width: 2, height: 22)
                    }
                }
            }
            if showsGrip {
                WindowDragArea(onDoubleClick: onDoubleClick,
                               onHorizontalDrag: { rightwards in Settings.shared.drawerOpen = rightwards })
            } else {
                WindowDragArea()
            }
        }
        .help(showsGrip ? "Drag sideways or double-click to open/close the drawer (⌘D)" : "")
    }
}

struct TitleBar: View {
    let onFullScreen: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.38), Color(white: 0.24)], startPoint: .top, endPoint: .bottom)
            WindowDragArea()
            Text("Wake Up Time")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color(white: 0.85))
                .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
                .allowsHitTesting(false)
            HStack {
                Spacer()
                Button(action: onFullScreen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(white: 0.85))
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Full Screen Clock (⌃⌘F)")
                .padding(.trailing, 6)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.6)).frame(height: 1) }
    }
}

// MARK: - LCD

struct LCDPanel: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var alarm = AlarmController.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.16),
                                    Color(red: 0.11, green: 0.15, blue: 0.24),
                                    Color(red: 0.03, green: 0.05, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.2, green: 0.27, blue: 0.4).opacity(0.5), .clear],
                           center: .center, startRadius: 10, endRadius: 260)
            // Glass reflection on the upper half
            LinearGradient(colors: [.white.opacity(0.04), .white.opacity(0.01)], startPoint: .top, endPoint: .bottom)
                .frame(height: Layout.lcdHeight / 2)
                .frame(maxHeight: .infinity, alignment: .top)
            WindowDragArea()
            SevenSegmentClock(date: alarm.now,
                              use24Hour: TimeFormat.uses24Hour(settings),
                              colonVisible: alarm.colonVisible,
                              digitHeight: 82)
                .allowsHitTesting(false)
            if alarm.phase != .off {
                Image(systemName: "bell.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.8, green: 0.87, blue: 1.0).opacity(0.8))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Bottom bar

struct BottomBar: View {
    @ObservedObject private var alarm = AlarmController.shared
    @ObservedObject private var settings = Settings.shared
    let onSleep: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            MainSwitch(isOn: $settings.alarmEnabled)
                .frame(width: Layout.switchArea)
            HUDView()
                .frame(width: Layout.hudWidth, height: Layout.hudHeight)
            SleepButton(action: onSleep)
                .disabled(alarm.phase == .off)
                .frame(width: Layout.sleepArea)
        }
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(white: 0.93), Color(white: 0.75)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) { Rectangle().fill(Color(white: 0.55)).frame(height: 1) }
    }
}

/// The round "Main Switch" with an LED that glows blue when the alarm is on.
struct MainSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.72)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(Color(white: 0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(isOn
                          ? RadialGradient(colors: [Color(red: 0.6, green: 0.85, blue: 1), Color(red: 0.1, green: 0.4, blue: 0.95)],
                                           center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 7)
                          : RadialGradient(colors: [Color(white: 0.35), Color(white: 0.15)],
                                           center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 7))
                    .frame(width: 12, height: 12)
                    .shadow(color: isOn ? Color(red: 0.3, green: 0.6, blue: 1) : .clear, radius: 5)
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Disable Alarm" : "Enable Alarm")
    }
}

struct SleepButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Sleep")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.32, green: 0.55, blue: 0.82))
                .frame(width: 70, height: 28)
                .background(
                    Capsule().fill(LinearGradient(colors: [.white, Color(white: 0.84)], startPoint: .top, endPoint: .bottom))
                )
                .overlay(Capsule().stroke(Color(white: 0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .help("Turn off the display until the alarm")
    }
}

struct StopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color(red: 0.72, green: 0.38, blue: 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Stop the alarm")
    }
}

// MARK: - HUD

/// The amber information display between the switch and the Sleep button.
struct HUDView: View {
    @ObservedObject private var alarm = AlarmController.shared
    @ObservedObject private var settings = Settings.shared

    private let ink = Color(red: 0.72, green: 0.38, blue: 0.1)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.78),
                                              Color(red: 0.98, green: 0.84, blue: 0.55)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(red: 0.85, green: 0.65, blue: 0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            content
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder private var content: some View {
        let use24 = TimeFormat.uses24Hour(settings)
        switch alarm.phase {
        case .off:
            lines("Alarm not set", TimeFormat.longDate(alarm.now))
        case .armed:
            lines("Alarm set",
                  "\(TimeFormat.time(hour: settings.alarmHour, minute: settings.alarmMinute, use24Hour: use24)) · \(alarm.fireDayLabel ?? "")",
                  emphasizeSecond: true)
        case .ringing:
            VStack(spacing: 3) {
                Text("Snooze")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 130, height: 16)
                    .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.92, green: 0.5, blue: 0.2), ink],
                                                              startPoint: .top, endPoint: .bottom)))
                Text("Press anywhere to snooze.")
                    .font(.system(size: 11))
                    .foregroundStyle(ink)
            }
        case .snoozing:
            lines("Snooze - \(alarm.snoozeUntil.map { TimeFormat.time($0, use24Hour: use24) } ?? "")",
                  "Alarm at \(TimeFormat.time(hour: settings.alarmHour, minute: settings.alarmMinute, use24Hour: use24))")
        }
    }

    private func lines(_ first: String, _ second: String, emphasizeSecond: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(first).font(.system(size: 13, weight: .medium))
            Text(second).font(.system(size: 11, weight: emphasizeSecond ? .bold : .regular))
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
