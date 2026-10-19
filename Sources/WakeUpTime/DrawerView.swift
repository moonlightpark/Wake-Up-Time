import SwiftUI

/// The right drawer: alarm time and sound settings.
struct DrawerView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var library = SoundLibrary.shared
    @ObservedObject private var preview = SoundPlayer.preview

    var body: some View {
        VStack(spacing: 10) {
            header("Alarm time")
            DatePicker("", selection: alarmTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.stepperField)
                .labelsHidden()
                .environment(\.locale, TimeFormat.uses24Hour(settings) ? Locale(identifier: "en_GB") : Locale(identifier: "en_US"))

            Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).offset(y: 1) }
                .padding(.vertical, 4)

            header("Sound")
            Picker("", selection: $settings.soundID) {
                Text("Random").tag(Settings.randomSoundID)
                Divider()
                ForEach(library.visibleItems(selected: settings.soundID)) { item in
                    Text(item.title).tag(item.id)
                }
            }
            .labelsHidden()
            .controlSize(.small)

            if let item = library.item(id: settings.soundID), !item.isAvailable {
                Text("Sound unavailable")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 4) {
                Image(systemName: "speaker.fill").font(.system(size: 9))
                Slider(value: $settings.volume, in: 0...1)
                    .controlSize(.mini)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 9))
            }
            .foregroundStyle(Color(white: 0.75))

            HStack {
                Toggle("Fade", isOn: $settings.fade)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(Color(white: 0.9))
                Spacer()
                Button(action: togglePreview) {
                    Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.3, green: 0.5, blue: 0.75))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(LinearGradient(colors: [.white, Color(white: 0.78)],
                                                                 startPoint: .top, endPoint: .bottom)))
                        .overlay(Circle().stroke(Color.black.opacity(0.4)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Test the alarm sound")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.19)], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
        .onChange(of: settings.volume) { _, value in
            if isPreviewing { preview.setVolume(Float(value)) }
        }
    }

    private var isPreviewing: Bool { preview.playingID != nil }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(white: 0.82))
            .shadow(color: .black.opacity(0.7), radius: 0, y: -1)
    }

    /// Changing the alarm time automatically turns the Main Switch on.
    private var alarmTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings.alarmHour, minute: settings.alarmMinute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.alarmHour = c.hour ?? 7
                settings.alarmMinute = c.minute ?? 0
                settings.alarmEnabled = true
            })
    }

    private func togglePreview() {
        if isPreviewing {
            preview.stop()
        } else {
            let item = library.resolve(settings.soundID)
            try? preview.play(item, volume: Float(settings.volume), loop: false)
        }
    }
}
