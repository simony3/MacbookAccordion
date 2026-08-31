import Foundation

struct ParameterSpec: Identifiable, Codable {
    let id: String
    let label: String
    let initial: Double
    let minimum: Double
    let maximum: Double
    let step: Double
    let decimals: Int
    let group: String
    var inverted = false

    func quantized(_ value: Double) -> Double {
        min(maximum, max(minimum, (value / step).rounded(.toNearestOrEven) * step))
    }

    static let all: [ParameterSpec] = [
        .init(id: "master", label: "音量", initial: 0.30, minimum: 0.05, maximum: 1.20, step: 0.01, decimals: 2, group: "轻松设置"),
        .init(id: "vel_max", label: "开合灵敏度", initial: 160, minimum: 30, maximum: 400, step: 1, decimals: 0, group: "轻松设置", inverted: true),
        .init(id: "fill_rate", label: "进气速度", initial: 2.2, minimum: 0.1, maximum: 8, step: 0.1, decimals: 1, group: "开合细节"),
        .init(id: "leak_rate", label: "漏气速度", initial: 0.12, minimum: 0, maximum: 2, step: 0.01, decimals: 2, group: "开合细节"),
        .init(id: "deadzone", label: "微小动作过滤", initial: 0.010, minimum: 0, maximum: 0.080, step: 0.001, decimals: 3, group: "开合细节"),
        .init(id: "rise_a", label: "力度上升平滑度", initial: 0.70, minimum: 0, maximum: 0.99, step: 0.01, decimals: 2, group: "开合细节"),
        .init(id: "fall_a", label: "力度下降平滑度", initial: 0.96, minimum: 0, maximum: 0.999, step: 0.001, decimals: 3, group: "开合细节"),
        .init(id: "attack_s", label: "起音时间（秒）", initial: 0.020, minimum: 0.001, maximum: 0.200, step: 0.001, decimals: 3, group: "声音细节"),
        .init(id: "release_s", label: "释音时间（秒）", initial: 0.120, minimum: 0.010, maximum: 1, step: 0.005, decimals: 3, group: "声音细节"),
        .init(id: "detune", label: "簧片厚度（失谐）", initial: 0.005, minimum: 0, maximum: 0.050, step: 0.001, decimals: 3, group: "声音细节"),
        .init(id: "noise", label: "气流与簧片噪声", initial: 0.008, minimum: 0, maximum: 0.080, step: 0.001, decimals: 3, group: "声音细节")
    ]
}

struct InstrumentParameters {
    private(set) var values = Dictionary(uniqueKeysWithValues: ParameterSpec.all.map { ($0.id, $0.initial) })
    subscript(_ key: String) -> Double { values[key]! }
    mutating func set(_ spec: ParameterSpec, to value: Double) { values[spec.id] = spec.quantized(value) }
    mutating func apply(_ preset: SoundPreset) {
        // Presets intentionally bypass slider quantization, as in the Python edition.
        for (key, value) in preset.values { values[key] = value }
    }
}

enum SoundPreset: String, CaseIterable, Identifiable {
    case classic = "经典", soft = "柔和", bright = "明亮", playful = "搞怪"
    var id: String { rawValue }
    var values: [String: Double] {
        let v: [Double]
        switch self {
        case .classic: v = [0.020, 0.120, 0.005, 0.008]
        case .soft: v = [0.045, 0.280, 0.003, 0.003]
        case .bright: v = [0.008, 0.080, 0.002, 0.004]
        case .playful: v = [0.015, 0.200, 0.022, 0.025]
        }
        return Dictionary(uniqueKeysWithValues: zip(["attack_s", "release_s", "detune", "noise"], v))
    }
    var symbol: String {
        switch self { case .classic: "pianokeys"; case .soft: "wind"; case .bright: "sun.max"; case .playful: "sparkles" }
    }
    var detail: String {
        switch self { case .classic: "熟悉的簧片声"; case .soft: "舒缓、绵长"; case .bright: "轻快、清脆"; case .playful: "一点不一样" }
    }
}
