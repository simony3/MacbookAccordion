import SwiftUI

struct PianoView: View {
    var model: InstrumentModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("你的琴键").font(.headline)
                Text("C\(4 + model.octave / 12) — B\(6 + model.octave / 12)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 10) {
                    Text("八度").font(.caption).foregroundStyle(.secondary)
                    Button { model.transpose(-12) } label: { Image(systemName: "minus") }
                        .disabled(model.octave <= -36).accessibilityLabel("降低一个八度")
                    Text(model.octave == 0 ? "0" : String(format: "%+d", model.octave / 12))
                        .font(.system(.body, design: .rounded).monospacedDigit()).frame(width: 24)
                    Button { model.transpose(12) } label: { Image(systemName: "plus") }
                        .disabled(model.octave >= 36).accessibilityLabel("升高一个八度")
                }.controlSize(.small)
            }
            GeometryReader { geometry in
                let whiteWidth = geometry.size.width / CGFloat(KeyboardMap.whiteNotes.count)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(KeyboardMap.whiteNotes, id: \.self) { note in
                            key(note, black: false).frame(width: whiteWidth, height: 144)
                        }
                    }
                    ForEach(KeyboardMap.blackNotes, id: \.self) { note in
                        let preceding = KeyboardMap.whiteNotes.filter { $0 < note }.count
                        key(note, black: true)
                            .frame(width: whiteWidth * 0.64, height: 98)
                            .offset(x: CGFloat(preceding) * whiteWidth - whiteWidth * 0.32)
                    }
                }
            }.frame(height: 145)
            HStack {
                Label("字母 / 数字键演奏，也可以按住屏幕琴键", systemImage: "keyboard")
                Spacer()
                Text(model.held.isEmpty ? "等待按键" : "\(model.held.count) 个音符")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private func key(_ midi: Int, black: Bool) -> some View {
        let down = model.held.values.contains(midi)
        let labels = KeyboardMap.labels(for: midi)
        return RoundedRectangle(cornerRadius: black ? 4 : 5)
            .fill(down ? Color.accentColor : black ? Color(white: 0.16) : Color(white: 0.98))
            .overlay {
                RoundedRectangle(cornerRadius: black ? 4 : 5)
                    .strokeBorder(black ? Color.black.opacity(0.5) : Color.black.opacity(0.18), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(black ? 0.2 : 0.04), radius: black ? 2 : 0, y: black ? 3 : 1)
            .overlay(alignment: .bottom) {
                VStack(spacing: 5) {
                    Text(labels.replacingOccurrences(of: "/", with: midi == 88 ? "/" : "\n"))
                        .font(.system(size: black ? 9 : 10, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.center)
                    if !black { Text(KeyboardMap.name(midi + model.octave)).font(.system(size: 8)).opacity(0.65) }
                }
                .foregroundStyle(down ? .white : black ? Color(white: 0.85) : Color(white: 0.4))
                .padding(.bottom, black ? 9 : 11)
            }
            .padding(.horizontal, black ? 0 : 0.5)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in model.noteOn(id: 128 + midi, midi: midi) }
                .onEnded { _ in model.noteOff(id: 128 + midi) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(KeyboardMap.name(midi + model.octave))，\(labels.isEmpty ? "屏幕琴键" : labels)")
            .accessibilityValue(down ? "按下" : "松开")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                model.noteOn(id: 128 + midi, midi: midi)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { model.noteOff(id: 128 + midi) }
            }
    }
}
