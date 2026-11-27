import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum TBClosedLidPowerSource: Equatable {
    case ac
    case battery
    case unknown
}

enum TBClosedLidPowerThermalState: Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unsupported
}

enum TBClosedLidPowerStopReason: Equatable {
    case seriousThermal
    case externalPowerRequired
    case batteryLevelUnavailable
    case lowBattery
    case criticalThermal
}

enum TBClosedLidPowerUnavailableReason: Equatable {
    case powerSourceUnknown
    case helperRequired
}

enum TBClosedLidPowerRestoreDecision: Equatable {
    case restorePreviousValue(Bool)
    case preserveExternalChange
    case noChangeRequired
}

struct TBClosedLidPowerLease: Codable, Equatable {
    let sessionID: String
    let bootSessionID: String
    let ownerUID: UInt32
    let originalSleepDisabled: Bool
    let overrideSleepDisabled: Bool
    let startedAtUptime: TimeInterval
    var heartbeatUptime: TimeInterval
    let expiresAtUptime: TimeInterval

    func isStructurallyValid(at uptime: TimeInterval) -> Bool {
        TBClosedLidPowerTransaction.isValidSessionID(sessionID)
            && TBClosedLidPowerTransaction.isValidSessionID(bootSessionID)
            && expiresAtUptime > uptime
            && heartbeatUptime <= uptime
            && expiresAtUptime > heartbeatUptime
            && expiresAtUptime - heartbeatUptime <= TBClosedLidPowerTransaction.maximumLeaseDuration
            && startedAtUptime <= heartbeatUptime
            && ownerUID != 0
            && overrideSleepDisabled
    }
}

enum TBClosedLidPowerLeaseDecision: Equatable {
    case keepActive
    case expireAndRestore(Bool)
    case preserveExternalChange
    case orphanWithoutMutation
}

/// Pure begin/end transaction decisions used by the future privileged helper.
/// Persistence and system-setting I/O remain outside this model.
enum TBClosedLidPowerTransaction {
    static let maximumLeaseDuration: TimeInterval = 120

    static func begin(currentValue: Bool, sessionID: String) -> Bool? {
        guard isValidSessionID(sessionID), !currentValue else { return nil }
        return currentValue
    }

    static func end(savedValue: Bool?, currentValue: Bool) -> TBClosedLidPowerRestoreDecision {
        guard let savedValue else { return .noChangeRequired }
        guard currentValue == true else { return .preserveExternalChange }
        return .restorePreviousValue(savedValue)
    }

    static func isValidSessionID(_ sessionID: String) -> Bool {
        guard (1...64).contains(sessionID.utf8.count) else { return false }
        return sessionID.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0)
        }
    }

    static func makeLease(
        sessionID: String,
        bootSessionID: String,
        ownerUID: UInt32,
        originalSleepDisabled: Bool,
        uptime: TimeInterval,
        duration: TimeInterval = maximumLeaseDuration
    ) -> TBClosedLidPowerLease? {
        guard isValidSessionID(sessionID), isValidSessionID(bootSessionID), ownerUID != 0, !originalSleepDisabled,
              duration > 0, duration <= maximumLeaseDuration else { return nil }
        return TBClosedLidPowerLease(
            sessionID: sessionID,
            bootSessionID: bootSessionID,
            ownerUID: ownerUID,
            originalSleepDisabled: originalSleepDisabled,
            overrideSleepDisabled: true,
            startedAtUptime: uptime,
            heartbeatUptime: uptime,
            expiresAtUptime: uptime + duration
        )
    }

    static func heartbeat(_ lease: TBClosedLidPowerLease, uptime: TimeInterval, duration: TimeInterval = maximumLeaseDuration) -> TBClosedLidPowerLease? {
        guard lease.isStructurallyValid(at: uptime), lease.expiresAtUptime > uptime,
              duration > 0, duration <= maximumLeaseDuration else { return nil }
        return TBClosedLidPowerLease(
            sessionID: lease.sessionID,
            bootSessionID: lease.bootSessionID,
            ownerUID: lease.ownerUID,
            originalSleepDisabled: lease.originalSleepDisabled,
            overrideSleepDisabled: lease.overrideSleepDisabled,
            startedAtUptime: lease.startedAtUptime,
            heartbeatUptime: uptime,
            expiresAtUptime: uptime + duration
        )
    }

    static func recoveryDecision(lease: TBClosedLidPowerLease?, currentSleepDisabled: Bool, currentBootSessionID: String, uptime: TimeInterval) -> TBClosedLidPowerLeaseDecision {
        guard let lease,
              isValidLeaseRecord(lease, uptime: uptime, currentBootSessionID: currentBootSessionID, allowExpired: true) else { return .orphanWithoutMutation }
        if lease.bootSessionID != currentBootSessionID {
            guard currentSleepDisabled == lease.overrideSleepDisabled else { return .preserveExternalChange }
            return .expireAndRestore(lease.originalSleepDisabled)
        }
        guard currentSleepDisabled == lease.overrideSleepDisabled else { return .preserveExternalChange }
        guard lease.expiresAtUptime <= uptime else { return .keepActive }
        return .expireAndRestore(lease.originalSleepDisabled)
    }

    static func isValidLeaseRecord(_ lease: TBClosedLidPowerLease, uptime: TimeInterval, currentBootSessionID: String? = nil, allowExpired: Bool = false) -> Bool {
        let sameBoot = currentBootSessionID == nil || currentBootSessionID == lease.bootSessionID
        return isValidSessionID(lease.sessionID)
            && isValidSessionID(lease.bootSessionID)
            && lease.ownerUID != 0
            && !lease.originalSleepDisabled
            && lease.overrideSleepDisabled
            && lease.startedAtUptime <= lease.heartbeatUptime
            && (!sameBoot || lease.heartbeatUptime <= uptime)
            && lease.expiresAtUptime > lease.heartbeatUptime
            && lease.expiresAtUptime - lease.heartbeatUptime <= maximumLeaseDuration
            && (!sameBoot || allowExpired || lease.expiresAtUptime > uptime)
    }
}

enum TBClosedLidPowerJournalError: Error, Equatable {
    case invalidDirectory
    case invalidFile
    case encodingFailed
}

enum TBClosedLidPowerCoordinatorError: Error, Equatable {
    case sessionAlreadyActive
    case sessionNotOwned
    case settingsWriteDidNotTakeEffect
    case malformedJournal
}

protocol TBClosedLidPowerSettingsStore {
    func readSleepDisabled() throws -> Bool
    func setSleepDisabled(_ disabled: Bool) throws
}

enum TBClosedLidPowerSessionEnd: Equatable {
    case restored(Bool)
    case preservedExternalChange
}

/// Serial transaction coordinator shared with the future helper target.
/// Callers supply privileged settings I/O; this model itself performs none.
final class TBClosedLidPowerSessionCoordinator {
    private let journal: TBClosedLidPowerJournal
    private let settings: TBClosedLidPowerSettingsStore
    private let lock = NSLock()

    init(journal: TBClosedLidPowerJournal, settings: TBClosedLidPowerSettingsStore) {
        self.journal = journal
        self.settings = settings
    }

    func begin(sessionID: String, bootSessionID: String, ownerUID: UInt32, uptime: TimeInterval) throws {
        // Reconcile a stale lease (including a previous boot) before admitting
        // another session. Concurrent begins still serialize below.
        _ = try recover(currentBootSessionID: bootSessionID, uptime: uptime)
        lock.lock()
        defer { lock.unlock() }
        if try journal.read(currentBootSessionID: bootSessionID, uptime: uptime) != nil {
            throw TBClosedLidPowerCoordinatorError.sessionAlreadyActive
        }
        let priorValue = try settings.readSleepDisabled()
        guard let lease = TBClosedLidPowerTransaction.makeLease(
            sessionID: sessionID,
            bootSessionID: bootSessionID,
            ownerUID: ownerUID,
            originalSleepDisabled: priorValue,
            uptime: uptime
        ) else {
            throw TBClosedLidPowerCoordinatorError.sessionAlreadyActive
        }

        // Durable recovery intent must exist before the system-wide mutation.
        try journal.write(lease)
        try settings.setSleepDisabled(true)
        guard try settings.readSleepDisabled() else {
            throw TBClosedLidPowerCoordinatorError.settingsWriteDidNotTakeEffect
        }
    }

    func heartbeat(sessionID: String, ownerUID: UInt32, bootSessionID: String, uptime: TimeInterval) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let lease = try journal.read(currentBootSessionID: bootSessionID, uptime: uptime),
              lease.sessionID == sessionID, lease.ownerUID == ownerUID,
              lease.bootSessionID == bootSessionID,
              let refreshed = TBClosedLidPowerTransaction.heartbeat(lease, uptime: uptime) else {
            throw TBClosedLidPowerCoordinatorError.sessionNotOwned
        }
        try journal.write(refreshed)
    }

    @discardableResult
    func end(sessionID: String, ownerUID: UInt32, bootSessionID: String, uptime: TimeInterval) throws -> TBClosedLidPowerSessionEnd {
        lock.lock()
        defer { lock.unlock() }
        guard let lease = try journal.read(currentBootSessionID: bootSessionID, uptime: uptime),
              lease.sessionID == sessionID, lease.ownerUID == ownerUID,
              lease.bootSessionID == bootSessionID else {
            throw TBClosedLidPowerCoordinatorError.sessionNotOwned
        }
        let current = try settings.readSleepDisabled()
        switch TBClosedLidPowerTransaction.end(savedValue: lease.originalSleepDisabled, currentValue: current) {
        case .restorePreviousValue(let previous):
            try settings.setSleepDisabled(previous)
            guard try settings.readSleepDisabled() == previous else {
                throw TBClosedLidPowerCoordinatorError.settingsWriteDidNotTakeEffect
            }
            try journal.remove()
            return .restored(previous)
        case .preserveExternalChange:
            try journal.remove()
            return .preservedExternalChange
        case .noChangeRequired:
            throw TBClosedLidPowerCoordinatorError.malformedJournal
        }
    }

    @discardableResult
    func recover(currentBootSessionID: String, uptime: TimeInterval) throws -> TBClosedLidPowerSessionEnd? {
        lock.lock()
        defer { lock.unlock() }
        guard let lease = try journal.read(currentBootSessionID: currentBootSessionID, uptime: uptime) else { return nil }
        let current = try settings.readSleepDisabled()
        switch TBClosedLidPowerTransaction.recoveryDecision(
            lease: lease,
            currentSleepDisabled: current,
            currentBootSessionID: currentBootSessionID,
            uptime: uptime
        ) {
        case .keepActive:
            return nil
        case .expireAndRestore(let previous):
            try settings.setSleepDisabled(previous)
            guard try settings.readSleepDisabled() == previous else {
                throw TBClosedLidPowerCoordinatorError.settingsWriteDidNotTakeEffect
            }
            try journal.remove()
            return .restored(previous)
        case .preserveExternalChange:
            try journal.remove()
            return .preservedExternalChange
        case .orphanWithoutMutation:
            throw TBClosedLidPowerCoordinatorError.malformedJournal
        }
    }
}

/// File-backed lease journal core. The production helper must instantiate this
/// only for its root-owned directory; tests inject a temporary directory.
struct TBClosedLidPowerJournal {
    let directoryURL: URL
    let expectedOwnerUID: UInt32
    private let fileManager: FileManager

    init(directoryURL: URL, expectedOwnerUID: UInt32 = UInt32(geteuid()), fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.expectedOwnerUID = expectedOwnerUID
        self.fileManager = fileManager
    }

    var fileURL: URL { directoryURL.appendingPathComponent("closed-lid-session.json", isDirectory: false) }

    func write(_ lease: TBClosedLidPowerLease) throws {
        guard TBClosedLidPowerTransaction.isValidLeaseRecord(lease, uptime: lease.heartbeatUptime, allowExpired: true) else {
            throw TBClosedLidPowerJournalError.encodingFailed
        }
        try validateDirectory(createIfMissing: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(lease)
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            #if canImport(Darwin)
            let descriptor = open(fileURL.path, O_RDONLY | O_NOFOLLOW)
            if descriptor >= 0 {
                _ = fsync(descriptor)
                close(descriptor)
            }
            let directoryDescriptor = open(directoryURL.path, O_RDONLY)
            if directoryDescriptor >= 0 {
                _ = fsync(directoryDescriptor)
                close(directoryDescriptor)
            }
            #endif
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
    }

    func read(currentBootSessionID: String, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> TBClosedLidPowerLease? {
        try validateDirectory(createIfMissing: false)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let values = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw TBClosedLidPowerJournalError.invalidFile }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == expectedOwnerUID,
              (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw TBClosedLidPowerJournalError.invalidFile
        }
        let lease = try JSONDecoder().decode(TBClosedLidPowerLease.self, from: Data(contentsOf: fileURL, options: [.mappedIfSafe]))
        guard TBClosedLidPowerTransaction.isValidLeaseRecord(lease, uptime: uptime, currentBootSessionID: currentBootSessionID, allowExpired: true) else {
            throw TBClosedLidPowerJournalError.invalidFile
        }
        return lease
    }

    func remove() throws {
        try validateDirectory(createIfMissing: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            let values = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw TBClosedLidPowerJournalError.invalidFile }
            try fileManager.removeItem(at: fileURL)
            #if canImport(Darwin)
            let descriptor = open(directoryURL.path, O_RDONLY)
            if descriptor >= 0 {
                _ = fsync(descriptor)
                close(descriptor)
            }
            #endif
        }
    }

    private func validateDirectory(createIfMissing: Bool) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            guard createIfMissing else { return }
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        }
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw TBClosedLidPowerJournalError.invalidDirectory
        }
        let attributes = try fileManager.attributesOfItem(atPath: directoryURL.path)
        guard (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == expectedOwnerUID else {
            throw TBClosedLidPowerJournalError.invalidDirectory
        }
    }
}

enum TBClosedLidPowerDecision: Equatable {
    case disabled
    case waitingForStream
    case eligibleOnAC(lidClosed: Bool)
    case eligibleOnBattery(lidClosed: Bool)
    case reduceStreamLoad(TBClosedLidPowerStopReason)
    case stopAndRestore(TBClosedLidPowerStopReason)
    case unavailable(TBClosedLidPowerUnavailableReason)
    case closedLidUnavailable(TBClosedLidPowerUnavailableReason)
}

struct TBClosedLidPowerObservation: Equatable {
    var enabled: Bool
    var streamActive: Bool
    var powerSource: TBClosedLidPowerSource
    var batteryPercent: Int?
    var allowsBattery: Bool
    var batteryStopThreshold: Int
    var thermalState: TBClosedLidPowerThermalState
    var lidClosed: Bool
    var helperAvailable: Bool
}

enum TBClosedLidPowerPolicy {
    static func evaluate(_ observation: TBClosedLidPowerObservation) -> TBClosedLidPowerDecision {
        guard observation.enabled else { return .disabled }
        guard observation.streamActive else { return .waitingForStream }

        if observation.thermalState == .critical {
            return .stopAndRestore(.criticalThermal)
        }
        if observation.thermalState == .serious {
            return .reduceStreamLoad(.seriousThermal)
        }

        switch observation.powerSource {
        case .unknown:
            return .unavailable(.powerSourceUnknown)
        case .ac:
            guard observation.lidClosed, !observation.helperAvailable else {
                return .eligibleOnAC(lidClosed: observation.lidClosed)
            }
            return .closedLidUnavailable(.helperRequired)
        case .battery:
            guard observation.allowsBattery else {
                return .stopAndRestore(.externalPowerRequired)
            }
            guard let batteryPercent = observation.batteryPercent,
                  (0...100).contains(batteryPercent) else {
                return .stopAndRestore(.batteryLevelUnavailable)
            }
            let threshold = min(max(observation.batteryStopThreshold, 0), 100)
            guard batteryPercent > threshold else {
                return .stopAndRestore(.lowBattery)
            }
            guard observation.lidClosed, !observation.helperAvailable else {
                return .eligibleOnBattery(lidClosed: observation.lidClosed)
            }
            return .closedLidUnavailable(.helperRequired)
        }
    }
}
