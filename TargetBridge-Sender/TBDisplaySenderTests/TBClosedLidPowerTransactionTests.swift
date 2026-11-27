import XCTest
@testable import TargetBridge

private final class TBTestSleepSettings: TBClosedLidPowerSettingsStore {
    var value = false
    var writes: [Bool] = []
    var failNextWrite = false

    func readSleepDisabled() throws -> Bool { value }

    func setSleepDisabled(_ disabled: Bool) throws {
        writes.append(disabled)
        if failNextWrite {
            failNextWrite = false
            return
        }
        value = disabled
    }
}

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

    func testLeaseEnforcesBoundedDurationAndSafeOwnerAndPriorState() {
        let now: TimeInterval = 10_000
        XCTAssertNotNil(TBClosedLidPowerTransaction.makeLease(sessionID: "s1", bootSessionID: "boot1", ownerUID: 501, originalSleepDisabled: false, uptime: now))
        XCTAssertNil(TBClosedLidPowerTransaction.makeLease(sessionID: "s1", bootSessionID: "boot1", ownerUID: 0, originalSleepDisabled: false, uptime: now))
        XCTAssertNil(TBClosedLidPowerTransaction.makeLease(sessionID: "s1", bootSessionID: "boot1", ownerUID: 501, originalSleepDisabled: true, uptime: now))
        XCTAssertNil(TBClosedLidPowerTransaction.makeLease(sessionID: "s1", bootSessionID: "boot1", ownerUID: 501, originalSleepDisabled: false, uptime: now, duration: 121))
    }

    func testHeartbeatRenewsOnlyUnexpiredValidLease() {
        let now: TimeInterval = 10_000
        let lease = try! XCTUnwrap(TBClosedLidPowerTransaction.makeLease(sessionID: "s1", bootSessionID: "boot1", ownerUID: 501, originalSleepDisabled: false, uptime: now))
        let refreshed = TBClosedLidPowerTransaction.heartbeat(lease, uptime: now + 20)
        XCTAssertEqual(refreshed?.heartbeatUptime, now + 20)
        XCTAssertEqual(refreshed?.expiresAtUptime, now + 140)
        XCTAssertNil(TBClosedLidPowerTransaction.heartbeat(lease, uptime: now + 121))
    }

    func testRecoveryKeepsLiveLeaseAndRestoresOnlyExpiredOwnedOverride() {
        let now: TimeInterval = 10_000
        let lease = try! XCTUnwrap(TBClosedLidPowerTransaction.makeLease(sessionID: "s1", bootSessionID: "boot1", ownerUID: 501, originalSleepDisabled: false, uptime: now))
        XCTAssertEqual(TBClosedLidPowerTransaction.recoveryDecision(lease: lease, currentSleepDisabled: true, currentBootSessionID: "boot1", uptime: now + 30), .keepActive)
        XCTAssertEqual(TBClosedLidPowerTransaction.recoveryDecision(lease: lease, currentSleepDisabled: true, currentBootSessionID: "boot1", uptime: now + 121), .expireAndRestore(false))
        XCTAssertEqual(TBClosedLidPowerTransaction.recoveryDecision(lease: lease, currentSleepDisabled: false, currentBootSessionID: "boot1", uptime: now + 121), .preserveExternalChange)
        XCTAssertEqual(TBClosedLidPowerTransaction.recoveryDecision(lease: lease, currentSleepDisabled: true, currentBootSessionID: "boot2", uptime: now + 1), .expireAndRestore(false))
    }

    func testRecoveryFailsClosedOnMalformedOrMissingJournalRecord() throws {
        let now: TimeInterval = 10_000
        XCTAssertEqual(TBClosedLidPowerTransaction.recoveryDecision(lease: nil, currentSleepDisabled: true, currentBootSessionID: "boot1", uptime: now), .orphanWithoutMutation)
        let good = try XCTUnwrap(TBClosedLidPowerTransaction.makeLease(sessionID: "s1", bootSessionID: "boot1", ownerUID: 501, originalSleepDisabled: false, uptime: now))
        let corrupted = TBClosedLidPowerLease(sessionID: good.sessionID, bootSessionID: good.bootSessionID, ownerUID: good.ownerUID, originalSleepDisabled: false, overrideSleepDisabled: false, startedAtUptime: good.startedAtUptime, heartbeatUptime: good.heartbeatUptime, expiresAtUptime: good.expiresAtUptime)
        XCTAssertEqual(TBClosedLidPowerTransaction.recoveryDecision(lease: corrupted, currentSleepDisabled: true, currentBootSessionID: "boot1", uptime: now + 121), .orphanWithoutMutation)
    }

    func testJournalWritesAtomicallyReadsAndRemovesPrivateLease() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = TBClosedLidPowerJournal(directoryURL: root)
        let now: TimeInterval = 10_000
        let lease = try XCTUnwrap(TBClosedLidPowerTransaction.makeLease(sessionID: "sessionA", bootSessionID: "boot1", ownerUID: 501, originalSleepDisabled: false, uptime: now))

        try journal.write(lease)
        XCTAssertEqual(try journal.read(currentBootSessionID: "boot1", uptime: now), lease)
        XCTAssertEqual(try journal.read(currentBootSessionID: "boot2", uptime: 1), lease)
        let directoryMode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: journal.fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryMode?.intValue, 0o700)
        XCTAssertEqual(fileMode?.intValue, 0o600)

        try journal.remove()
        XCTAssertNil(try journal.read(currentBootSessionID: "boot1", uptime: now))
    }

    func testJournalRejectsUnsafeDirectoryPermissionsAndMalformedRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let journal = TBClosedLidPowerJournal(directoryURL: root)
        XCTAssertThrowsError(try journal.read(currentBootSessionID: "boot1"))
        XCTAssertThrowsError(try journal.write(try XCTUnwrap(TBClosedLidPowerTransaction.makeLease(sessionID: "s", bootSessionID: "boot1", ownerUID: 501, originalSleepDisabled: false, uptime: 10_000))))

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try Data("{invalid".utf8).write(to: journal.fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.fileURL.path)
        XCTAssertThrowsError(try journal.read(currentBootSessionID: "boot1"))
    }

    func testJournalRejectsSymbolicLinkInsteadOfFollowingIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("closed-lid-session.json"), withDestinationURL: outside)
        let journal = TBClosedLidPowerJournal(directoryURL: root)
        XCTAssertThrowsError(try journal.read(currentBootSessionID: "boot1"))
    }

    func testCoordinatorPersistsBeforeOverrideAndRestoresExactPreviousValue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = TBClosedLidPowerJournal(directoryURL: root)
        let settings = TBTestSleepSettings()
        let coordinator = TBClosedLidPowerSessionCoordinator(journal: journal, settings: settings)
        try coordinator.begin(sessionID: "session", bootSessionID: "boot1", ownerUID: 501, uptime: 10_000)
        XCTAssertTrue(settings.value)
        XCTAssertNotNil(try journal.read(currentBootSessionID: "boot1", uptime: 10_000))
        XCTAssertEqual(try coordinator.end(sessionID: "session", ownerUID: 501, bootSessionID: "boot1", uptime: 10_010), .restored(false))
        XCTAssertFalse(settings.value)
        XCTAssertNil(try journal.read(currentBootSessionID: "boot1", uptime: 10_010))
    }

    func testCoordinatorPreservesExternalChangeAndRejectsOtherOwners() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = TBClosedLidPowerJournal(directoryURL: root)
        let settings = TBTestSleepSettings()
        let coordinator = TBClosedLidPowerSessionCoordinator(journal: journal, settings: settings)
        try coordinator.begin(sessionID: "session", bootSessionID: "boot1", ownerUID: 501, uptime: 10_000)
        XCTAssertThrowsError(try coordinator.end(sessionID: "session", ownerUID: 502, bootSessionID: "boot1", uptime: 10_001))
        settings.value = false
        XCTAssertEqual(try coordinator.end(sessionID: "session", ownerUID: 501, bootSessionID: "boot1", uptime: 10_002), .preservedExternalChange)
        XCTAssertFalse(settings.value)
    }

    func testCoordinatorHeartbeatRenewsOwnedLeaseAndRejectsExpiredSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = TBClosedLidPowerJournal(directoryURL: root)
        let settings = TBTestSleepSettings()
        let coordinator = TBClosedLidPowerSessionCoordinator(journal: journal, settings: settings)
        try coordinator.begin(sessionID: "session", bootSessionID: "boot1", ownerUID: 501, uptime: 10_000)
        try coordinator.heartbeat(sessionID: "session", ownerUID: 501, bootSessionID: "boot1", uptime: 10_090)
        XCTAssertEqual(try journal.read(currentBootSessionID: "boot1", uptime: 10_090)?.expiresAtUptime, 10_210)
        XCTAssertThrowsError(try coordinator.heartbeat(sessionID: "session", ownerUID: 501, bootSessionID: "boot1", uptime: 10_211))
    }

    func testCoordinatorRecoversOnBootChangeAndDoesNotOverwriteNewSleepValue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = TBClosedLidPowerJournal(directoryURL: root)
        let settings = TBTestSleepSettings()
        let coordinator = TBClosedLidPowerSessionCoordinator(journal: journal, settings: settings)
        try coordinator.begin(sessionID: "session", bootSessionID: "boot1", ownerUID: 501, uptime: 10_000)
        XCTAssertEqual(try coordinator.recover(currentBootSessionID: "boot2", uptime: 5), .restored(false))
        XCTAssertFalse(settings.value)
        XCTAssertNil(try journal.read(currentBootSessionID: "boot2", uptime: 5))

        try coordinator.begin(sessionID: "second", bootSessionID: "boot2", ownerUID: 501, uptime: 6)
        settings.value = false
        XCTAssertEqual(try coordinator.recover(currentBootSessionID: "boot2", uptime: 7), .preservedExternalChange)
        XCTAssertFalse(settings.value)
    }

    func testNewBeginRecoversExpiredPriorLeaseBeforeStartingNextSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = TBClosedLidPowerJournal(directoryURL: root)
        let settings = TBTestSleepSettings()
        let coordinator = TBClosedLidPowerSessionCoordinator(journal: journal, settings: settings)
        try coordinator.begin(sessionID: "first", bootSessionID: "boot1", ownerUID: 501, uptime: 10_000)
        try coordinator.begin(sessionID: "second", bootSessionID: "boot2", ownerUID: 501, uptime: 5)
        XCTAssertTrue(settings.value)
        let lease = try XCTUnwrap(journal.read(currentBootSessionID: "boot2", uptime: 5))
        XCTAssertEqual(lease.sessionID, "second")
    }

    func testFailedRestoreKeepsJournalForNextRecoveryAttempt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = TBClosedLidPowerJournal(directoryURL: root)
        let settings = TBTestSleepSettings()
        let coordinator = TBClosedLidPowerSessionCoordinator(journal: journal, settings: settings)
        try coordinator.begin(sessionID: "session", bootSessionID: "boot1", ownerUID: 501, uptime: 10_000)
        settings.failNextWrite = true
        XCTAssertThrowsError(try coordinator.end(sessionID: "session", ownerUID: 501, bootSessionID: "boot1", uptime: 10_001))
        XCTAssertNotNil(try journal.read(currentBootSessionID: "boot1", uptime: 10_121))
        XCTAssertEqual(try coordinator.recover(currentBootSessionID: "boot1", uptime: 10_121), .restored(false))
        XCTAssertFalse(settings.value)
    }
}
