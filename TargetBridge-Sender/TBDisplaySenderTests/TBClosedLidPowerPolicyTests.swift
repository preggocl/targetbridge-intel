import XCTest
@testable import TargetBridge

final class TBClosedLidPowerPolicyTests: XCTestCase {
    func testDisabledAddonNeverRequestsPowerChangesEvenWhenThermalStateIsCritical() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(enabled: false, streamActive: true, thermalState: .critical)
        )

        XCTAssertEqual(result, .disabled)
    }

    func testEnabledAddonWaitsUntilCaptureIsStreaming() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(enabled: true, streamActive: false)
        )

        XCTAssertEqual(result, .waitingForStream)
    }

    func testStreamingOnACIsEligibleForLidOverride() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(enabled: true, streamActive: true, lidClosed: true, helperAvailable: true)
        )

        XCTAssertEqual(result, .eligibleOnAC(lidClosed: true))
    }

    func testBatteryUseStopsAtConfiguredThreshold() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(
                enabled: true,
                streamActive: true,
                powerSource: .battery,
                batteryPercent: 25,
                allowsBattery: true
            )
        )

        XCTAssertEqual(result, .stopAndRestore(.lowBattery))
    }

    func testBatteryUseIsRejectedWhenBatteryModeIsOff() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(enabled: true, streamActive: true, powerSource: .battery, batteryPercent: 80)
        )

        XCTAssertEqual(result, .stopAndRestore(.externalPowerRequired))
    }

    func testUnknownBatteryLevelIsUnsafeWhenBatteryModeIsEnabled() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(enabled: true, streamActive: true, powerSource: .battery, allowsBattery: true)
        )

        XCTAssertEqual(result, .stopAndRestore(.batteryLevelUnavailable))
    }

    func testSeriousThermalStateRequestsReducedStreamLoad() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(enabled: true, streamActive: true, thermalState: .serious)
        )

        XCTAssertEqual(result, .reduceStreamLoad(.seriousThermal))
    }

    func testCriticalThermalStateStopsStreamBeforeOtherPowerChecks() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(
                enabled: true,
                streamActive: true,
                powerSource: .unknown,
                thermalState: .critical
            )
        )

        XCTAssertEqual(result, .stopAndRestore(.criticalThermal))
    }

    func testUnknownPowerSourceNeverCountsAsExternalPower() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(enabled: true, streamActive: true, powerSource: .unknown)
        )

        XCTAssertEqual(result, .unavailable(.powerSourceUnknown))
    }

    func testClosedLidRequiresReadyPrivilegedHelper() {
        let result = TBClosedLidPowerPolicy.evaluate(
            observation(enabled: true, streamActive: true, lidClosed: true, helperAvailable: false)
        )

        XCTAssertEqual(result, .closedLidUnavailable(.helperRequired))
    }

    private func observation(
        enabled: Bool,
        streamActive: Bool,
        powerSource: TBClosedLidPowerSource = .ac,
        batteryPercent: Int? = nil,
        allowsBattery: Bool = false,
        batteryStopThreshold: Int = 25,
        thermalState: TBClosedLidPowerThermalState = .nominal,
        lidClosed: Bool = false,
        helperAvailable: Bool = false
    ) -> TBClosedLidPowerObservation {
        TBClosedLidPowerObservation(
            enabled: enabled,
            streamActive: streamActive,
            powerSource: powerSource,
            batteryPercent: batteryPercent,
            allowsBattery: allowsBattery,
            batteryStopThreshold: batteryStopThreshold,
            thermalState: thermalState,
            lidClosed: lidClosed,
            helperAvailable: helperAvailable
        )
    }
}
