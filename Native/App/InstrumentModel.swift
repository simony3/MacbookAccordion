import AppKit
import Observation

@MainActor @Observable
final class InstrumentModel {
    var parameters = InstrumentParameters()
    var preset: SoundPreset? = .classic
    var octave = 0
    var inspectorVisible = false
    var helpVisible = false
    var forceSimulation = false
    private(set) var sensorAvailable = false
    private(set) var connecting = true
    private(set) var angle = 45.0
    private(set) var bellows = BellowsState()
    private(set) var held: [Int: Int] = [:]
    private(set) var audioError: String?
    private(set) var started = false
    @ObservationIgnored private let audio = InstrumentAudio()
    @ObservationIgnored private let sensor = LidSensor()
    @ObservationIgnored private var input: KeyboardInput?
    @ObservationIgnored private var previousTime: Double?
    @ObservationIgnored private var simulationAngle = 45.0
    @ObservationIgnored private var previousSimulation: Bool?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored let preview: Bool

    init(preview: Bool = false) { self.preview = preview }
    var simulated: Bool { forceSimulation || !sensorAvailable }
    var playing: String {
        held.sorted { $0.key < $1.key }.map { KeyboardMap.name($0.value + octave) }.joined(separator: " · ")
    }
    var status: String { connecting ? "正在连接屏幕控制…" : simulated ? "键盘试玩模式" : "屏幕控制已连接" }

    func start() {
        guard !started, !preview else { return }
        started = true
        audio.onStatus = { [weak self] error in self?.audioError = error }
        audio.start()
        input = KeyboardInput(model: self)
        input?.install()
        sensor.start { [weak self] angle, time in self?.tick(sensorAngle: angle, time: time) }
        for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification] {
            notificationTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.releaseAll() }
            })
        }
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                                                                                     object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.releaseAll(); self?.previousTime = nil }
        })
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                                     object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconnect(); self?.audio.start() }
        })
    }

    func stop() {
        releaseAll(); sensor.stop(); audio.stop(); input?.uninstall(); input = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()
        started = false
        previousTime = nil
    }

    private func tick(sensorAngle: Double?, time: Double) {
        guard started else { return }
        connecting = false
        sensorAvailable = sensorAngle != nil
        angle = simulated ? simulationAngle : sensorAngle!
        let dt = previousTime.map { time - $0 } ?? 1.0 / 60
        // Rebase after sleep / changing input source, so a discontinuity is not a bellows gesture.
        if previousTime == nil || previousSimulation != simulated || dt > 0.5 {
            bellows = BellowsState(angle: angle)
        } else { bellows.advance(angle: angle, dt: dt, parameters: parameters) }
        previousTime = time
        previousSimulation = simulated
        publishAudio()
    }

    func set(_ spec: ParameterSpec, value: Double) {
        parameters.set(spec, to: value)
        if SoundPreset.classic.values[spec.id] != nil { preset = nil }
        publishAudio()
    }
    func choose(_ style: SoundPreset) { parameters.apply(style); preset = style; publishAudio() }
    func transpose(_ delta: Int) { octave = KeyboardMap.clampedOctave(octave + delta); publishAudio() }
    func resetOctave() { octave = 0; publishAudio() }
    func reset() {
        parameters = InstrumentParameters(); preset = .classic; octave = 0
        simulationAngle = 45; inspectorVisible = false; forceSimulation = false
        publishAudio()
    }
    func noteOn(id: Int, midi: Int) {
        guard held[id] == nil else { return }
        held[id] = midi; publishAudio()
    }
    func noteOff(id: Int) { held.removeValue(forKey: id); publishAudio() }
    func releaseAll() { held.removeAll(); input?.clearModifiers(); audio.bridge.silence(); publishAudio() }
    func simulate(_ direction: Double) { if simulated { simulationAngle = min(110, max(0, simulationAngle + direction * 3)) } }
    func retryAudio() { audio.start(); publishAudio() }
    func reconnect() {
        connecting = true; previousTime = nil
        sensor.start { [weak self] angle, time in self?.tick(sensorAngle: angle, time: time) }
    }
    private func publishAudio() { audio.bridge.update(parameters: parameters, bellows: bellows.intensity, held: held, octave: octave) }
}
