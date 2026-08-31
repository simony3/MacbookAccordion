import Foundation
import IOKit.hid

/// Uses the same HID match and feature report as pybooklid 1.0.0.
/// All potentially blocking IOKit calls stay on the sensor queue.
final class LidSensor {
    private let queue = DispatchQueue(label: "games.macaca.macbookaccordion.native.lid", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    func start(deliver: @escaping (Double?, Double) -> Void) {
        queue.async { [self] in
            disconnect()
            connect()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 60.0, leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let angle = read()
                let time = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async { deliver(angle, time) }
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() { queue.async { [self] in disconnect() } }

    private func connect() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Int] = [kIOHIDVendorIDKey: LidReport.vendor, kIOHIDProductIDKey: LidReport.product,
                                   kIOHIDDeviceUsagePageKey: LidReport.usagePage, kIOHIDDeviceUsageKey: LidReport.usage]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        self.manager = manager
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in devices {
            if IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                device = candidate
                if read() != nil { return }
                IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
                device = nil
            }
        }
    }

    private func read() -> Double? {
        guard let device else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = UInt8(LidReport.reportID)
        var length = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, LidReport.reportID, &bytes, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        return LidReport.angle(from: Array(bytes.prefix(length)))
    }

    private func disconnect() {
        timer?.cancel(); timer = nil
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
    }
}
