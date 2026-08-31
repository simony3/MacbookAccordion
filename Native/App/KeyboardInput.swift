import AppKit

@MainActor
final class KeyboardInput {
    private weak var model: InstrumentModel?
    private var monitor: Any?
    private var modifiers = Set<UInt16>()
    init(model: InstrumentModel) { self.model = model }

    func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }
    func uninstall() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    func clearModifiers() { modifiers.removeAll() }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let model, NSApp.isActive, NSApp.keyWindow?.identifier?.rawValue == "instrument",
              !model.helpVisible else { return event }
        let code = Int(event.keyCode)
        // Release an owned note even if Command/Option was pressed after its key-down.
        if event.type == .keyUp, model.held[code] != nil { model.noteOff(id: code); return nil }
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) else { return event }
        if event.type == .flagsChanged {
            let flags: [UInt16: NSEvent.ModifierFlags] = [56: .shift, 60: .shift, 59: .control, 62: .control]
            guard let flag = flags[event.keyCode] else { return event }
            if modifiers.contains(event.keyCode) {
                modifiers.remove(event.keyCode)
                model.transpose(flag == .shift ? 12 : -12)
            } else if event.modifierFlags.contains(flag) { modifiers.insert(event.keyCode) }
            return nil
        }
        if event.type == .keyUp, code == 48 { model.resetOctave(); return nil }
        if event.type == .keyDown {
            if code == 53 { NSApp.terminate(nil); return nil }
            if code == 48 { return nil }
            if model.simulated, [125, 126].contains(code) {
                if !event.isARepeat { model.simulate(code == 126 ? 1 : -1) }
                return nil
            }
            if let note = KeyboardMap.byCode[code] {
                if !event.isARepeat { model.noteOn(id: code, midi: note.midi) }
                return nil
            }
        }
        return event
    }
}
