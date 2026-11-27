import Foundation

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

/// Pure begin/end transaction decisions used by the future privileged helper.
/// Persistence and system-setting I/O remain outside this model.
enum TBClosedLidPowerTransaction {
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
