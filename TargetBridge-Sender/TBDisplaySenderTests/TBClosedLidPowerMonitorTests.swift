import XCTest
@testable import TargetBridge

final class TBClosedLidPowerMonitorTests: XCTestCase {
    func testBatteryPercentageSupportsPercentAndCapacityUnits() {
        XCTAssertEqual(TBClosedLidPowerMonitor.batteryPercentage(current: 25, maximum: 100), 25)
        XCTAssertEqual(TBClosedLidPowerMonitor.batteryPercentage(current: 2_500, maximum: 10_000), 25)
    }

    func testBatteryPercentageRejectsMissingOrInvalidCapacity() {
        XCTAssertNil(TBClosedLidPowerMonitor.batteryPercentage(current: 25, maximum: nil))
        XCTAssertNil(TBClosedLidPowerMonitor.batteryPercentage(current: nil, maximum: 100))
        XCTAssertNil(TBClosedLidPowerMonitor.batteryPercentage(current: -1, maximum: 100))
        XCTAssertNil(TBClosedLidPowerMonitor.batteryPercentage(current: 101, maximum: 100))
        XCTAssertNil(TBClosedLidPowerMonitor.batteryPercentage(current: 1, maximum: 0))
    }

    @MainActor
    func testStopMonitoringRemovesThermalNotificationObserver() async {
        let center = NotificationCenter()
        var thermalState: TBClosedLidPowerThermalState = .nominal
        let monitor = TBClosedLidPowerMonitor(
            notificationCenter: center,
            powerSourceReader: { .init(source: .ac, currentCapacity: nil, maximumCapacity: nil) },
            thermalStateReader: { thermalState }
        )

        monitor.startMonitoring()
        thermalState = .critical
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(monitor.snapshot.thermalState, .critical)

        monitor.stopMonitoring()
        thermalState = .fair
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(monitor.snapshot.thermalState, .critical)
    }
}
