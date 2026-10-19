import AppKit
import SwiftUI

/// A borderless window covering one screen with the selected clock style.
final class FullScreenClockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, onClose: @escaping () -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .black
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: FullScreenClockView(onClose: onClose))
        setFrame(screen.frame, display: true)
    }
}

struct FullScreenClockView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var alarm = AlarmController.shared
    let onClose: () -> Void

    var body: some View {
        let style = ClockStyle(rawValue: settings.clockStyle) ?? .digital
        let use24 = TimeFormat.uses24Hour(settings)
        GeometryReader { geo in
            // Keep the banner and info bar legible on large displays.
            let scale = max(1, geo.size.height / 900)
            ZStack(alignment: .bottom) {
                ClockFace(style: style, date: alarm.now, use24Hour: use24, colonVisible: alarm.colonVisible)
                    .contentShape(Rectangle())
                    .onTapGesture { alarm.snooze() }

                VStack(spacing: 18) {
                    if alarm.phase == .ringing {
                        ringingBanner
                    }
                    infoBar(use24: use24, light: style.isLight)
                }
                .scaleEffect(scale, anchor: .bottom)
                .padding(.bottom, 28 * scale)
            }
        }
        .ignoresSafeArea()
    }

    private var ringingBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text("Snooze").font(.system(size: 22, weight: .bold))
                Text("Press anywhere to snooze.").font(.system(size: 14))
            }
            StopButton { alarm.stop() }
                .scaleEffect(1.6)
                .padding(.leading, 8)
        }
        .foregroundStyle(Color(red: 0.72, green: 0.38, blue: 0.1))
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.78), Color(red: 0.98, green: 0.84, blue: 0.55)],
                                 startPoint: .top, endPoint: .bottom)))
        .onTapGesture { alarm.snooze() }
    }

    private func infoBar(use24: Bool, light: Bool) -> some View {
        HStack(spacing: 22) {
            switch alarm.phase {
            case .off:
                Label("Alarm off", systemImage: "bell.slash")
            case .armed, .ringing:
                Label("\(TimeFormat.time(hour: settings.alarmHour, minute: settings.alarmMinute, use24Hour: use24)) \(alarm.fireDayLabel ?? "")",
                      systemImage: "bell.fill")
            case .snoozing:
                Label("Snooze - \(alarm.snoozeUntil.map { TimeFormat.time($0, use24Hour: use24) } ?? "")",
                      systemImage: "zzz")
                Button("Stop Alarm") { alarm.stop() }
                    .buttonStyle(.plain)
                    .underline()
            }
            Label(TimeFormat.longDate(alarm.now), systemImage: "calendar")
            Button(action: onClose) {
                Label("Press ESC to Quit", systemImage: "escape")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13))
        .foregroundStyle(light ? Color.black.opacity(0.55) : Color.white.opacity(0.55))
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Capsule().fill(light ? Color.black.opacity(0.06) : Color.white.opacity(0.07)))
    }
}
