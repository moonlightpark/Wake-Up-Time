import Foundation
import Combine

/// A sound file the user added in Preferences ▸ Sounds.
struct CustomSound: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var path: String
}

/// All persistent preferences, backed by UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    // Alarm
    @Published var alarmEnabled: Bool { didSet { save(alarmEnabled, "alarmEnabled") } }
    @Published var alarmHour: Int { didSet { save(alarmHour, "alarmHour") } }
    @Published var alarmMinute: Int { didSet { save(alarmMinute, "alarmMinute") } }

    // Sound (drawer)
    @Published var soundID: String { didSet { save(soundID, "soundID") } }
    @Published var volume: Double { didSet { save(volume, "volume") } }
    @Published var fade: Bool { didSet { save(fade, "fade") } }

    // General preferences
    @Published var adjustSystemVolume: Bool { didSet { save(adjustSystemVolume, "adjustSystemVolume") } }
    @Published var use24Hour: Bool { didSet { save(use24Hour, "use24Hour") } }
    @Published var flashSeparators: Bool { didSet { save(flashSeparators, "flashSeparators") } }
    @Published var keepOnTop: Bool { didSet { save(keepOnTop, "keepOnTop") } }
    @Published var keepAwake: Bool { didSet { save(keepAwake, "keepAwake") } }
    @Published var snoozeMinutes: Int { didSet { save(snoozeMinutes, "snoozeMinutes") } }

    // Sounds preferences
    @Published var hiddenSoundIDs: Set<String> { didSet { save(Array(hiddenSoundIDs), "hiddenSoundIDs") } }
    @Published var customSounds: [CustomSound] {
        didSet { defaults.set(try? JSONEncoder().encode(customSounds), forKey: "customSounds") }
    }

    // Clocks preferences
    @Published var clockStyle: String { didSet { save(clockStyle, "clockStyle") } }

    // Window state and dismissed warnings
    @Published var drawerOpen: Bool { didSet { save(drawerOpen, "drawerOpen") } }
    @Published var suppressSleepWarning: Bool { didSet { save(suppressSleepWarning, "suppressSleepWarning") } }
    @Published var suppressQuitWarning: Bool { didSet { save(suppressQuitWarning, "suppressQuitWarning") } }

    static let randomSoundID = "random"

    private init() {
        let d = UserDefaults.standard
        alarmEnabled = d.object(forKey: "alarmEnabled") as? Bool ?? false
        alarmHour = d.object(forKey: "alarmHour") as? Int ?? 7
        alarmMinute = d.object(forKey: "alarmMinute") as? Int ?? 0
        soundID = d.string(forKey: "soundID") ?? "synth:digital"
        volume = d.object(forKey: "volume") as? Double ?? 0.7
        fade = d.object(forKey: "fade") as? Bool ?? true
        adjustSystemVolume = d.object(forKey: "adjustSystemVolume") as? Bool ?? true
        use24Hour = d.object(forKey: "use24Hour") as? Bool ?? false
        flashSeparators = d.object(forKey: "flashSeparators") as? Bool ?? true
        keepOnTop = d.object(forKey: "keepOnTop") as? Bool ?? false
        keepAwake = d.object(forKey: "keepAwake") as? Bool ?? true
        snoozeMinutes = d.object(forKey: "snoozeMinutes") as? Int ?? 9
        hiddenSoundIDs = Set(d.stringArray(forKey: "hiddenSoundIDs") ?? [])
        if let data = d.data(forKey: "customSounds"),
           let list = try? JSONDecoder().decode([CustomSound].self, from: data) {
            customSounds = list
        } else {
            customSounds = []
        }
        clockStyle = d.string(forKey: "clockStyle") ?? ClockStyle.digital.rawValue
        drawerOpen = d.object(forKey: "drawerOpen") as? Bool ?? true
        suppressSleepWarning = d.bool(forKey: "suppressSleepWarning")
        suppressQuitWarning = d.bool(forKey: "suppressQuitWarning")
    }

    func resetWarnings() {
        suppressSleepWarning = false
        suppressQuitWarning = false
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

enum TimeFormat {
    /// True when the user's locale prefers a 24-hour clock.
    static var systemUses24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !format.contains("a")
    }

    /// The "24-hour display" preference forces 24h; otherwise the system setting decides.
    static func uses24Hour(_ settings: Settings) -> Bool {
        settings.use24Hour || systemUses24Hour
    }

    static func time(_ date: Date, use24Hour: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return f.string(from: date)
    }

    static func time(hour: Int, minute: Int, use24Hour: Bool) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return time(date, use24Hour: use24Hour)
    }

    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
}
