import Foundation

struct BellowsState {
    private(set) var air = 0.0
    private(set) var intensity = 0.0
    private(set) var velocity = 0.0
    private var previousAngle: Double

    init(angle: Double = 45) { previousAngle = angle }

    mutating func advance(angle: Double, dt: Double, velocityDT: Double? = nil, parameters p: InstrumentParameters) {
        velocity = (angle - previousAngle) / max(1e-6, velocityDT ?? dt)
        previousAngle = angle
        var raw = min(1, abs(velocity) / max(1e-6, p["vel_max"]))
        if raw < p["deadzone"] { raw = 0 }
        air = min(1, max(0, air + (raw * p["fill_rate"] - p["leak_rate"]) * dt))
        let a = air > intensity ? p["rise_a"] : p["fall_a"]
        intensity = intensity * a + air * (1 - a)
    }
}

enum LidReport {
    static let vendor = 0x05AC
    static let product = 0x8104
    static let usagePage = 0x0020
    static let usage = 0x008A
    static let reportID = 1
    static func angle(from bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3, bytes[0] == reportID else { return nil }
        return Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
    }
}
