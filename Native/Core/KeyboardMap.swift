import Foundation

struct NoteKey: Identifiable, Codable {
    let keyCode: Int
    let label: String
    let midi: Int
    var id: Int { keyCode }
}

enum KeyboardMap {
    static let keys: [NoteKey] = [
        .init(keyCode: 12, label: "Q", midi: 60), .init(keyCode: 13, label: "W", midi: 62),
        .init(keyCode: 14, label: "E", midi: 64), .init(keyCode: 15, label: "R", midi: 65),
        .init(keyCode: 17, label: "T", midi: 67), .init(keyCode: 16, label: "Y", midi: 69),
        .init(keyCode: 32, label: "U", midi: 71), .init(keyCode: 34, label: "I", midi: 72),
        .init(keyCode: 31, label: "O", midi: 74), .init(keyCode: 35, label: "P", midi: 76),
        .init(keyCode: 18, label: "1", midi: 61), .init(keyCode: 19, label: "2", midi: 63),
        .init(keyCode: 21, label: "4", midi: 66), .init(keyCode: 23, label: "5", midi: 68),
        .init(keyCode: 22, label: "6", midi: 70), .init(keyCode: 28, label: "8", midi: 73),
        .init(keyCode: 25, label: "9", midi: 75), .init(keyCode: 29, label: "0", midi: 78),
        .init(keyCode: 6, label: "Z", midi: 72), .init(keyCode: 7, label: "X", midi: 74),
        .init(keyCode: 8, label: "C", midi: 76), .init(keyCode: 9, label: "V", midi: 77),
        .init(keyCode: 11, label: "B", midi: 79), .init(keyCode: 45, label: "N", midi: 81),
        .init(keyCode: 46, label: "M", midi: 83), .init(keyCode: 43, label: ",", midi: 84),
        .init(keyCode: 47, label: ".", midi: 86), .init(keyCode: 44, label: "/", midi: 88),
        .init(keyCode: 0, label: "A", midi: 73), .init(keyCode: 1, label: "S", midi: 75),
        .init(keyCode: 2, label: "D", midi: 78), .init(keyCode: 3, label: "F", midi: 80),
        .init(keyCode: 5, label: "G", midi: 82), .init(keyCode: 4, label: "H", midi: 85),
        .init(keyCode: 38, label: "J", midi: 87), .init(keyCode: 40, label: "K", midi: 90),
        .init(keyCode: 37, label: "L", midi: 92), .init(keyCode: 41, label: ";", midi: 94)
    ]
    static let byCode = Dictionary(uniqueKeysWithValues: keys.map { ($0.keyCode, $0) })
    static let whiteNotes = (60...95).filter { [0, 2, 4, 5, 7, 9, 11].contains($0 % 12) }
    static let blackNotes = (60...95).filter { !whiteNotes.contains($0) }
    static func labels(for midi: Int) -> String { keys.filter { $0.midi == midi }.map(\.label).joined(separator: "/") }
    static func clampedMIDI(_ midi: Int) -> Int { min(127, max(0, midi)) }
    static func clampedOctave(_ semitones: Int) -> Int { min(36, max(-36, semitones)) }
    static func name(_ midi: Int) -> String {
        let n = clampedMIDI(midi)
        return ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][n % 12] + "\(n / 12 - 1)"
    }
    static func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
}
