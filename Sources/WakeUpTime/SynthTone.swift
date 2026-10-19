import Foundation

/// Built-in alarm sounds, synthesized at runtime so the app ships no audio assets.
enum SynthTone: String, CaseIterable {
    case digital, pulse, ringer, chime, sunrise, cosmic

    var title: String {
        switch self {
        case .digital: return "Digital"
        case .pulse: return "Pulse"
        case .ringer: return "Ringer"
        case .chime: return "Chime"
        case .sunrise: return "Sunrise"
        case .cosmic: return "Cosmic"
        }
    }

    private static let sampleRate = 44_100.0
    private static var cache: [SynthTone: Data] = [:]

    /// One loop of the sound as a 16-bit mono WAV file.
    var wavData: Data {
        if let data = Self.cache[self] { return data }
        let data = Self.wav(render())
        Self.cache[self] = data
        return data
    }

    private func render() -> [Float] {
        let sr = Self.sampleRate
        func buffer(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * sr)) }
        let twoPi = 2.0 * Double.pi
        var buf: [Float]

        switch self {
        case .digital:
            // The classic "beep-beep-beep-beep" of a bedside alarm clock.
            let beep = 0.075, gap = 0.055
            buf = buffer(4 * (beep + gap) + 0.6)
            for b in 0..<4 {
                let start = Int(Double(b) * (beep + gap) * sr)
                let n = Int(beep * sr)
                for j in 0..<n {
                    let t = Double(j) / sr
                    let env = Self.edges(j, n, ramp: Int(0.003 * sr))
                    let s = sin(twoPi * 2050 * t) + 0.25 * sin(twoPi * 6150 * t)
                    buf[start + j] += Float(0.5 * env * s)
                }
            }

        case .pulse:
            // Three soft sine swells.
            let len = 0.25, gap = 0.12
            buf = buffer(3 * (len + gap) + 0.7)
            for b in 0..<3 {
                let start = Int(Double(b) * (len + gap) * sr)
                let n = Int(len * sr)
                for j in 0..<n {
                    let t = Double(j) / sr
                    let env = pow(sin(Double.pi * Double(j) / Double(n)), 2)
                    buf[start + j] += Float(0.6 * env * sin(twoPi * 784 * t))
                }
            }

        case .ringer:
            // Old telephone bell: two close tones chopped by a 20 Hz clapper.
            buf = buffer(3.4)
            for ringStart in [0.0, 1.4] {
                let start = Int(ringStart * sr)
                let n = Int(1.0 * sr)
                for j in 0..<n {
                    let t = Double(j) / sr
                    let clapper = sin(twoPi * 20 * t) > 0 ? 1.0 : 0.25
                    let env = Self.edges(j, n, ramp: Int(0.01 * sr))
                    let s = (sin(twoPi * 440 * t) + sin(twoPi * 480 * t)) * 0.35
                    buf[start + j] += Float(s * clapper * env)
                }
            }

        case .chime:
            // Bell arpeggio C6 E6 G6 C7 with inharmonic partials.
            buf = buffer(3.2)
            let notes = [1046.5, 1318.5, 1568.0, 2093.0]
            let partials: [(ratio: Double, amp: Double)] = [(1, 1), (2.76, 0.35), (5.4, 0.15)]
            for (i, f) in notes.enumerated() {
                let start = Int(Double(i) * 0.32 * sr)
                for j in 0..<(buf.count - start) {
                    let t = Double(j) / sr
                    let attack = min(1, t / 0.002)
                    var s = 0.0
                    for p in partials {
                        s += p.amp * sin(twoPi * f * p.ratio * t) * exp(-t / (0.9 / sqrt(p.ratio)))
                    }
                    buf[start + j] += Float(0.3 * attack * s)
                }
            }

        case .sunrise:
            // Gentle rising marimba-like pentatonic run.
            buf = buffer(3.2)
            let steps = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]
            for (i, semis) in steps.enumerated() {
                let f = 523.25 * pow(2, Double(semis) / 12)
                let start = Int(Double(i) * 0.2 * sr)
                for j in 0..<(buf.count - start) {
                    let t = Double(j) / sr
                    let attack = min(1, t / 0.003)
                    let s = (sin(twoPi * f * t) + 0.2 * sin(twoPi * 4 * f * t)) * exp(-t / 0.4)
                    buf[start + j] += Float(0.35 * attack * s)
                }
            }

        case .cosmic:
            // Slowly sweeping, shimmering tone with a circular echo so it loops seamlessly.
            let seconds = 4.0
            buf = buffer(seconds)
            var phase = 0.0, phase2 = 0.0
            for j in 0..<buf.count {
                let t = Double(j) / sr
                let base = 520 + 180 * sin(twoPi * t / seconds)
                let f = base * (1 + 0.015 * sin(twoPi * 6 * t))
                phase += twoPi * f / sr
                phase2 += twoPi * f * 1.5 / sr
                let trem = 0.7 + 0.3 * sin(twoPi * 2 * t)
                buf[j] = Float(0.4 * trem * (sin(phase) + 0.3 * sin(phase2)))
            }
            let delay = Int(0.25 * sr)
            let dry = buf
            for j in 0..<buf.count {
                buf[j] += 0.35 * dry[(j - delay + dry.count) % dry.count]
            }
        }

        Self.normalize(&buf, peak: 0.85)
        return buf
    }

    private static func edges(_ i: Int, _ n: Int, ramp: Int) -> Double {
        min(1, Double(i) / Double(ramp), Double(n - i) / Double(ramp))
    }

    private static func normalize(_ buf: inout [Float], peak: Float) {
        let maxValue = buf.reduce(0) { max($0, abs($1)) }
        guard maxValue > 0 else { return }
        let gain = peak / maxValue
        for i in buf.indices { buf[i] *= gain }
    }

    private static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let rate = UInt32(sampleRate)
        let dataSize = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(dataSize)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32767)
            u16(UInt16(bitPattern: v))
        }
        return data
    }
}
