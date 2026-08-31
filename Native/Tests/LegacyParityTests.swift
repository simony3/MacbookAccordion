import XCTest
@testable import AccordionCore

final class LegacyParityTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "LegacyContract", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testAllParameterMetadataMatchesLegacy() throws {
        let expected = try XCTUnwrap(try fixture()["parameters"] as? [[String: Any]])
        XCTAssertEqual(expected.count, ParameterSpec.all.count)
        for (spec, row) in zip(ParameterSpec.all, expected) {
            XCTAssertEqual(spec.id, row["id"] as? String)
            XCTAssertEqual(spec.label, row["label"] as? String)
            XCTAssertEqual(spec.group, row["group"] as? String)
            XCTAssertEqual(spec.initial, try XCTUnwrap(row["initial"] as? Double), accuracy: 1e-12)
            XCTAssertEqual(spec.minimum, try XCTUnwrap(row["minimum"] as? Double), accuracy: 1e-12)
            XCTAssertEqual(spec.maximum, try XCTUnwrap(row["maximum"] as? Double), accuracy: 1e-12)
            XCTAssertEqual(spec.step, try XCTUnwrap(row["step"] as? Double), accuracy: 1e-12)
            XCTAssertEqual(spec.inverted, row["inverted"] as? Bool)
            XCTAssertEqual(".\(spec.decimals)f", row["format"] as? String)
        }
    }

    func testPresetsAndCompleteKeyboardMapMatchLegacy() throws {
        let data = try fixture()
        let presets = try XCTUnwrap(data["presets"] as? [String: [String: Double]])
        XCTAssertEqual(presets.count, SoundPreset.allCases.count)
        for style in SoundPreset.allCases { XCTAssertEqual(style.values, presets[style.rawValue]) }
        let keys = try XCTUnwrap(data["keys"] as? [[String: Any]])
        XCTAssertEqual(keys.count, KeyboardMap.keys.count)
        for (key, row) in zip(KeyboardMap.keys, keys) {
            XCTAssertEqual(key.label, row["label"] as? String)
            XCTAssertEqual(key.midi, row["midi"] as? Int)
        }
        XCTAssertEqual(Set(KeyboardMap.keys.map(\.keyCode)).count, keys.count)
        XCTAssertEqual(KeyboardMap.keys.filter { $0.midi == 72 }.map(\.label), ["I", "Z"])
    }

    func testBellowsTraceMatchesPython() throws {
        let trace = try XCTUnwrap(try fixture()["bellows"] as? [[String: Double]])
        var state = BellowsState()
        for frame in trace {
            state.advance(angle: frame["angle"]!, dt: frame["dt"]!, parameters: InstrumentParameters())
            XCTAssertEqual(state.air, frame["air"]!, accuracy: 1e-11)
            XCTAssertEqual(state.intensity, frame["bellows"]!, accuracy: 1e-11)
            XCTAssertEqual(state.velocity, frame["vel"]!, accuracy: 1e-8)
        }
    }

    func testAudioEnvelopePhasesAndRetuningMatchPython() throws {
        let expected = try XCTUnwrap(try fixture()["audio"] as? [Double])
        let kernel = SynthKernel()
        kernel.settings.noise = 0
        kernel.settings.bellows = 0.72
        var rendered: [Float] = []
        for block in 0..<40 {
            if block == 0 { kernel.setNote(id: 12, midi: 60) }
            if block == 3 { kernel.setNote(id: 34, midi: 72); kernel.setNote(id: 6, midi: 72) }
            if block == 7 { kernel.setNote(id: 12, midi: 72); kernel.setNote(id: 34, midi: 84); kernel.setNote(id: 6, midi: 84) }
            if block == 10 { kernel.setNote(id: 34, midi: nil) }
            if block == 13 { kernel.setNote(id: 12, midi: nil); kernel.setNote(id: 6, midi: nil) }
            for _ in 0..<256 { rendered.append(kernel.sample()) }
        }
        XCTAssertEqual(rendered.count, expected.count)
        let maxError = zip(rendered, expected).map { abs(Double($0) - $1) }.max()!
        print("Legacy DSP maximum absolute sample error: \(maxError)")
        XCTAssertLessThan(maxError, 0.00002, "Float32 Python versus native DSP: \(maxError)")
        XCTAssertTrue(rendered.suffix(256).allSatisfy { $0 == 0 })
    }

    func testNoBellowsIsSilentAndPanicClearsPendingBlock() {
        let kernel = SynthKernel()
        kernel.setNote(id: 0, midi: 69)
        XCTAssertTrue((0..<1024).allSatisfy { _ in kernel.sample() == 0 })
        kernel.settings.bellows = 1
        kernel.settings.noise = 0
        XCTAssertTrue((0..<257).contains { _ in abs(kernel.sample()) > 0.001 })
        kernel.reset()
        XCTAssertTrue((0..<1024).allSatisfy { _ in kernel.sample() == 0 })
    }

    func testExtremeChordIsFiniteAndClipped() {
        let kernel = SynthKernel()
        kernel.settings.master = 1.2
        kernel.settings.bellows = 1
        kernel.settings.noise = 0.08
        for (i, key) in KeyboardMap.keys.enumerated() { kernel.setNote(id: i, midi: key.midi + 36) }
        for _ in 0..<4096 {
            let value = kernel.sample()
            XCTAssertTrue(value.isFinite && abs(value) <= 1)
        }
    }

    func testSliderQuantizationAndOctaveBoundaries() {
        for spec in ParameterSpec.all {
            XCTAssertEqual(spec.quantized(-100), spec.minimum)
            XCTAssertEqual(spec.quantized(1000), spec.maximum)
        }
        XCTAssertEqual(KeyboardMap.clampedOctave(-48), -36)
        XCTAssertEqual(KeyboardMap.clampedOctave(48), 36)
        XCTAssertEqual(KeyboardMap.clampedMIDI(140), 127)
        XCTAssertEqual(KeyboardMap.frequency(69), 440)
        var parameters = InstrumentParameters()
        parameters.apply(.soft)
        XCTAssertEqual(parameters["detune"], 0.003)
        XCTAssertEqual(parameters["master"], 0.30)
        XCTAssertEqual(parameters["vel_max"], 160)
    }

    func testHIDReportContractAndMalformedInput() {
        XCTAssertEqual(LidReport.angle(from: [1, 90, 0, 0, 0, 0, 0, 0]), 90)
        XCTAssertEqual(LidReport.angle(from: [1, 1, 1]), 257)
        XCTAssertNil(LidReport.angle(from: []))
        XCTAssertNil(LidReport.angle(from: [1, 90]))
        XCTAssertNil(LidReport.angle(from: [2, 90, 0]))
    }
}
