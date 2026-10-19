import AVFoundation
import Combine
import Foundation

struct SoundItem: Identifiable, Hashable {
    enum Source: Hashable {
        case synth(SynthTone)
        case file(URL)
    }

    enum Kind: String {
        case builtIn = "Built-in"
        case system = "System"
        case custom = "Custom"
    }

    let id: String
    var title: String
    let source: Source
    let kind: Kind

    var isAvailable: Bool {
        switch source {
        case .synth: return true
        case .file(let url): return FileManager.default.fileExists(atPath: url.path)
        }
    }
}

enum SoundError: LocalizedError {
    case unsupportedFormat
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported audio format"
        case .playbackFailed: return "Audio for the selected sound is not supported."
        }
    }
}

/// The catalog of alarm sounds: synthesized built-ins, macOS system sounds and user files.
final class SoundLibrary: ObservableObject {
    static let shared = SoundLibrary()

    @Published private(set) var items: [SoundItem] = []
    private let builtIn: [SoundItem]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let synth = SynthTone.allCases.map {
            SoundItem(id: "synth:\($0.rawValue)", title: $0.title, source: .synth($0), kind: .builtIn)
        }
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let system = files
            .filter { ["aiff", "aif", "caf", "wav", "mp3", "m4a"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return SoundItem(id: "system:\(name)", title: name, source: .file(url), kind: .system)
            }
        builtIn = synth + system

        Settings.shared.$customSounds
            .sink { [weak self] customs in self?.rebuild(customs) }
            .store(in: &cancellables)
    }

    private func rebuild(_ customs: [CustomSound]) {
        items = builtIn + customs.map {
            SoundItem(id: $0.id, title: $0.title, source: .file(URL(fileURLWithPath: $0.path)), kind: .custom)
        }
    }

    func item(id: String) -> SoundItem? {
        items.first { $0.id == id }
    }

    /// Sounds offered in the drawer: everything not hidden, plus the current selection.
    func visibleItems(selected: String? = nil) -> [SoundItem] {
        let hidden = Settings.shared.hiddenSoundIDs
        return items.filter { !hidden.contains($0.id) || $0.id == selected }
    }

    /// Resolves the drawer selection to a concrete sound, picking one when "Random" is chosen.
    func resolve(_ soundID: String) -> SoundItem {
        let fallback = items[0]
        if soundID == Settings.randomSoundID {
            let pool = visibleItems().filter(\.isAvailable)
            return pool.randomElement() ?? fallback
        }
        return item(id: soundID) ?? fallback
    }

    func makePlayer(for item: SoundItem) throws -> AVAudioPlayer {
        switch item.source {
        case .synth(let tone):
            return try AVAudioPlayer(data: tone.wavData, fileTypeHint: AVFileType.wav.rawValue)
        case .file(let url):
            return try AVAudioPlayer(contentsOf: url)
        }
    }

    // MARK: Custom sounds

    func addCustom(_ url: URL) throws {
        guard let probe = try? AVAudioPlayer(contentsOf: url), probe.duration > 0 else {
            throw SoundError.unsupportedFormat
        }
        let sound = CustomSound(id: "custom:\(UUID().uuidString)",
                                title: url.deletingPathExtension().lastPathComponent,
                                path: url.path)
        Settings.shared.customSounds.append(sound)
    }

    func removeCustom(id: String) {
        let settings = Settings.shared
        settings.customSounds.removeAll { $0.id == id }
        settings.hiddenSoundIDs.remove(id)
        if settings.soundID == id { settings.soundID = builtIn[0].id }
    }

    func rename(id: String, to title: String) {
        guard let i = Settings.shared.customSounds.firstIndex(where: { $0.id == id }) else { return }
        Settings.shared.customSounds[i].title = title
    }
}

/// Plays one sound at a time, optionally looping with a gradual fade-in.
final class SoundPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    /// Shared player for the play buttons in the drawer and preferences.
    static let preview = SoundPlayer()

    @Published private(set) var playingID: String?

    private var player: AVAudioPlayer?
    private var repeatTimer: Timer?
    private var fadeTimer: Timer?
    private var looping = false

    func play(_ item: SoundItem, volume: Float, loop: Bool, fadeIn: TimeInterval? = nil) throws {
        stop()
        let p = try SoundLibrary.shared.makePlayer(for: item)
        p.delegate = self
        looping = loop

        // Synthesized tones loop seamlessly; short files get a pause between repeats.
        let seamless: Bool
        if case .synth = item.source { seamless = true } else { seamless = p.duration >= 2.5 }
        p.numberOfLoops = (loop && seamless) ? -1 : 0
        p.volume = fadeIn == nil ? volume : 0
        p.prepareToPlay()
        guard p.play() else { throw SoundError.playbackFailed }
        player = p
        playingID = item.id

        if loop && !seamless {
            let t = Timer(timeInterval: p.duration + 0.5, repeats: true) { [weak self] _ in
                guard let p = self?.player else { return }
                p.currentTime = 0
                p.play()
            }
            RunLoop.main.add(t, forMode: .common)
            repeatTimer = t
        }

        if let fadeIn, fadeIn > 0 {
            let start = Date()
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
                let progress = min(1, Date().timeIntervalSince(start) / fadeIn)
                self?.player?.volume = volume * Float(progress)
                if progress >= 1 { timer.invalidate() }
            }
            RunLoop.main.add(t, forMode: .common)
            fadeTimer = t
        }
    }

    func setVolume(_ volume: Float) {
        fadeTimer?.invalidate()
        player?.volume = volume
    }

    func stop() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        fadeTimer?.invalidate()
        fadeTimer = nil
        player?.stop()
        player = nil
        playingID = nil
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        if !looping && p === player {
            player = nil
            playingID = nil
        }
    }
}
