import Combine
import Foundation

extension Notification.Name {
    static let alarmDidStartRinging = Notification.Name("WUTAlarmDidStartRinging")
}

/// Drives the clock tick and the alarm lifecycle: off → armed → ringing ⇄ snoozing → armed (next day).
final class AlarmController: ObservableObject {
    static let shared = AlarmController()

    enum Phase {
        case off, armed, ringing, snoozing
    }

    /// Current time, published twice a second (drives the flashing separators).
    @Published private(set) var now = Date()
    @Published private(set) var phase: Phase = .off
    @Published private(set) var fireDate: Date?
    @Published private(set) var snoozeUntil: Date?
    @Published private(set) var ringingSoundTitle: String?

    /// An alarm missed by more than this (e.g. the Mac was asleep) is skipped, not rung late.
    private let missedAlarmGrace: TimeInterval = 3600
    private let fadeDuration: TimeInterval = 30

    private let settings = Settings.shared
    private let player = SoundPlayer()
    private var timer: Timer?
    private var lastHalfSecond = 0
    private var savedVolume: Float?
    private var savedMute: Bool?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Publishers.CombineLatest3(settings.$alarmEnabled, settings.$alarmHour, settings.$alarmMinute)
            .sink { [weak self] enabled, hour, minute in
                self?.reschedule(enabled: enabled, hour: hour, minute: minute)
            }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var colonVisible: Bool {
        !settings.flashSeparators || now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) < 0.5
    }

    /// "Today" or "Tomorrow" for the next alarm.
    var fireDayLabel: String? {
        guard let fireDate else { return nil }
        return Calendar.current.isDateInToday(fireDate) ? "Today" : "Tomorrow"
    }

    // MARK: Actions

    func snooze() {
        guard phase == .ringing else { return }
        silence()
        snoozeUntil = Date().addingTimeInterval(TimeInterval(settings.snoozeMinutes * 60))
        phase = .snoozing
    }

    /// Stops ringing/snoozing and re-arms the same time for the next day.
    func stop() {
        guard phase == .ringing || phase == .snoozing else { return }
        silence()
        snoozeUntil = nil
        fireDate = Self.nextOccurrence(hour: settings.alarmHour, minute: settings.alarmMinute, after: Date())
        phase = .armed
    }

    /// Called on quit so the system volume is restored.
    func shutdown() {
        silence()
    }

    // MARK: Internals

    private func reschedule(enabled: Bool, hour: Int, minute: Int) {
        if phase == .ringing || phase == .snoozing { silence() }
        snoozeUntil = nil
        guard enabled else {
            fireDate = nil
            phase = .off
            return
        }
        fireDate = Self.nextOccurrence(hour: hour, minute: minute, after: Date())
        phase = .armed
    }

    private func tick() {
        let t = Date()
        let halfSecond = Int(t.timeIntervalSince1970 * 2)
        if halfSecond != lastHalfSecond {
            lastHalfSecond = halfSecond
            now = t
        }

        switch phase {
        case .armed:
            guard let fireDate, t >= fireDate else { return }
            if t.timeIntervalSince(fireDate) < missedAlarmGrace {
                ring()
            } else {
                self.fireDate = Self.nextOccurrence(hour: settings.alarmHour, minute: settings.alarmMinute, after: t)
            }
        case .snoozing:
            if let snoozeUntil, t >= snoozeUntil { ring() }
        case .off, .ringing:
            break
        }
    }

    private func ring() {
        phase = .ringing
        snoozeUntil = nil

        let volume = Float(settings.volume)
        var playerVolume = volume
        if settings.adjustSystemVolume {
            savedVolume = SystemAudio.volume
            savedMute = SystemAudio.isMuted
            SystemAudio.isMuted = false
            SystemAudio.volume = volume
            playerVolume = 1
        }

        let library = SoundLibrary.shared
        let item = library.resolve(settings.soundID)
        let fade = settings.fade ? fadeDuration : nil
        do {
            try player.play(item, volume: playerVolume, loop: true, fadeIn: fade)
            ringingSoundTitle = item.title
        } catch {
            // Never stay silent: fall back to the first built-in tone.
            let fallback = library.items[0]
            try? player.play(fallback, volume: playerVolume, loop: true, fadeIn: fade)
            ringingSoundTitle = fallback.title
        }

        Power.wakeDisplay()
        NotificationCenter.default.post(name: .alarmDidStartRinging, object: self)
    }

    private func silence() {
        player.stop()
        ringingSoundTitle = nil
        if let savedVolume { SystemAudio.volume = savedVolume }
        if let savedMute { SystemAudio.isMuted = savedMute }
        savedVolume = nil
        savedMute = nil
    }

    static func nextOccurrence(hour: Int, minute: Int, after date: Date) -> Date? {
        Calendar.current.nextDate(after: date,
                                  matching: DateComponents(hour: hour, minute: minute, second: 0),
                                  matchingPolicy: .nextTime)
    }
}
