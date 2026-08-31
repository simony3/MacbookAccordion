import Foundation

struct SynthSettings {
    var master: Double = 0.30
    var attack: Double = 0.020
    var release: Double = 0.120
    var detune: Double = 0.005
    var noise: Double = 0.008
    var bellows: Double = 0
    init() {}
    init(parameters p: InstrumentParameters, bellows: Double) {
        master = p["master"]; attack = p["attack_s"]; release = p["release_s"]
        detune = p["detune"]; noise = p["noise"]; self.bellows = bellows
    }
}

/// Audio-thread-owned, preallocated DSP. Keep the original 256-sample envelope ramps
/// even when Core Audio requests a different number of frames.
final class SynthKernel {
    static let sampleRate = 44_100.0
    static let blockSize = 256
    static let voiceCount = 256
    private struct Voice {
        var frequency = 0.0
        var phase1 = 0.0
        var phase2 = 0.0
        var envelope = 0.0
        var held = false
    }
    private var voices = [Voice](repeating: Voice(), count: voiceCount)
    private var block = [Float](repeating: 0, count: blockSize)
    private var cursor = blockSize
    private var randomState: UInt64 = 0x12A0B6C8D354E79F
    var settings = SynthSettings()

    func setNote(id: Int, midi: Int?) {
        guard voices.indices.contains(id) else { return }
        if let midi {
            voices[id].frequency = KeyboardMap.frequency(midi)
            voices[id].held = true
        } else { voices[id].held = false }
    }

    func reset() {
        for i in voices.indices { voices[i] = Voice() }
        for i in block.indices { block[i] = 0 }
        cursor = Self.blockSize
    }

    func sample() -> Float {
        if cursor == Self.blockSize { generateBlock(); cursor = 0 }
        let value = block[cursor]
        cursor += 1
        return value
    }

    private func uniform() -> Double {
        randomState ^= randomState >> 12
        randomState ^= randomState << 25
        randomState ^= randomState >> 27
        let bits = randomState &* 2_685_821_657_736_338_717
        return (Double(bits >> 11) + 1) / (9_007_199_254_740_992 + 1)
    }

    private func generateBlock() {
        for i in block.indices { block[i] = 0 }
        let frames = Self.blockSize
        let attackStep = 1 / max(1e-6, settings.attack * Self.sampleRate)
        let releaseStep = 1 / max(1e-6, settings.release * Self.sampleRate)
        for k in voices.indices {
            var voice = voices[k]
            guard voice.held || voice.envelope > 0 else { continue }
            let end = voice.held ? min(1, voice.envelope + attackStep * Double(frames))
                : max(0, voice.envelope - releaseStep * Double(frames))
            if end <= 0 && !voice.held { voices[k] = Voice(); continue }
            let inc1 = voice.frequency * (1 - settings.detune) / Self.sampleRate
            let inc2 = voice.frequency * (1 + settings.detune) / Self.sampleRate
            for i in 0..<frames {
                let p1 = (voice.phase1 + inc1 * Double(i)).truncatingRemainder(dividingBy: 1)
                let p2 = (voice.phase2 + inc2 * Double(i)).truncatingRemainder(dividingBy: 1)
                let signal = tanh(1.6 * (0.6 * (2 * p1 - 1) + 0.4 * (2 * p2 - 1)))
                let envelope = voice.envelope + (end - voice.envelope) * Double(i) / Double(frames - 1)
                block[i] += Float(signal * envelope)
            }
            voice.phase1 = (voice.phase1 + inc1 * Double(frames)).truncatingRemainder(dividingBy: 1)
            voice.phase2 = (voice.phase2 + inc2 * Double(frames)).truncatingRemainder(dividingBy: 1)
            voice.envelope = end
            voices[k] = voice
        }
        for i in block.indices {
            if settings.bellows > 0 && settings.noise > 0 {
                // Box–Muller: same standard-normal distribution as numpy.random.randn.
                let noise = sqrt(-2 * log(uniform())) * cos(2 * Double.pi * uniform())
                block[i] += Float(noise * settings.noise * settings.bellows * 0.7)
            }
            block[i] = min(1, max(-1, block[i] * Float(settings.master * settings.bellows)))
        }
    }
}
