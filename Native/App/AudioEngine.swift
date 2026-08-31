import AVFoundation

/// UI writes under a short lock. The realtime callback only tries the lock;
/// if the UI owns it, rendering continues with the last complete state.
final class AudioBridge {
    private let lock = NSLock()
    private var notes = [Int?](repeating: nil, count: SynthKernel.voiceCount)
    private var settings = SynthSettings()
    private var resetRequested = false
    private let kernel = SynthKernel()

    func update(parameters: InstrumentParameters, bellows: Double, held: [Int: Int], octave: Int) {
        lock.lock()
        settings = SynthSettings(parameters: parameters, bellows: bellows)
        for i in notes.indices { notes[i] = nil }
        for (id, midi) in held where notes.indices.contains(id) { notes[id] = KeyboardMap.clampedMIDI(midi + octave) }
        lock.unlock()
    }

    func silence() {
        lock.lock()
        resetRequested = true
        for i in notes.indices { notes[i] = nil }
        lock.unlock()
    }

    func render(frames: Int, buffers: UnsafeMutablePointer<AudioBufferList>) {
        if lock.try() {
            if resetRequested { kernel.reset(); resetRequested = false }
            kernel.settings = settings
            for i in notes.indices { kernel.setNote(id: i, midi: notes[i]) }
            lock.unlock()
        }
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        for frame in 0..<frames {
            let value = kernel.sample()
            for buffer in list {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for channel in 0..<Int(buffer.mNumberChannels) {
                    data[frame * Int(buffer.mNumberChannels) + channel] = value
                }
            }
        }
    }
}

@MainActor
final class InstrumentAudio {
    let bridge = AudioBridge()
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    var onStatus: ((String?) -> Void)?

    func start() {
        stop()
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: SynthKernel.sampleRate, channels: 1)!
        let bridge = bridge
        let source = AVAudioSourceNode(format: format) { _, _, count, buffers in
            bridge.render(frames: Int(count), buffers: buffers)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        self.engine = engine
        do {
            engine.prepare()
            try engine.start()
            onStatus?(nil)
        } catch { onStatus?(error.localizedDescription) }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.start() }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.stop()
        engine = nil
        bridge.silence()
    }
}
