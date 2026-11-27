import XCTest
@testable import TargetBridge

final class TBClosedLidPowerTransactionTests: XCTestCase {
    func testBeginCapturesPriorEnabledValueBeforeOverride() {
        XCTAssertEqual(TBClosedLidPowerTransaction.begin(currentValue: false, sessionID: "session_123"), false)
    }

    func testBeginRejectsExistingSleepOverrideAndInvalidIdentifiers() {
        XCTAssertNil(TBClosedLidPowerTransaction.begin(currentValue: true, sessionID: "session"))
        XCTAssertNil(TBClosedLidPowerTransaction.begin(currentValue: false, sessionID: ""))
        XCTAssertNil(TBClosedLidPowerTransaction.begin(currentValue: false, sessionID: "session id"))
        XCTAssertNil(TBClosedLidPowerTransaction.begin(currentValue: false, sessionID: String(repeating: "a", count: 65)))
    }

    func testEndRestoresSavedValueOnlyWhenOverrideIsStillOwned() {
        XCTAssertEqual(TBClosedLidPowerTransaction.end(savedValue: false, currentValue: true), .restorePreviousValue(false))
        XCTAssertEqual(TBClosedLidPowerTransaction.end(savedValue: false, currentValue: false), .preserveExternalChange)
        XCTAssertEqual(TBClosedLidPowerTransaction.end(savedValue: true, currentValue: true), .restorePreviousValue(true))
    }

    func testEndWithoutRecordedSessionNeverMutatesSetting() {
        XCTAssertEqual(TBClosedLidPowerTransaction.end(savedValue: nil, currentValue: true), .noChangeRequired)
        XCTAssertEqual(TBClosedLidPowerTransaction.end(savedValue: nil, currentValue: false), .noChangeRequired)
    }

    func testSessionIdentifierAcceptsBoundedASCIIAllowlist() {
        XCTAssertTrue(TBClosedLidPowerTransaction.isValidSessionID("aZ09-_"))
        XCTAssertFalse(TBClosedLidPowerTransaction.isValidSessionID("é"))
        XCTAssertFalse(TBClosedLidPowerTransaction.isValidSessionID(String(repeating: "x", count: 65)))
    }
}
