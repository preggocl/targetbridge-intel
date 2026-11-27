import Darwin
import Foundation
import Security

private enum HelperFailure: Error {
    case invalidIdentity
    case invalidBootSession
    case settingUnavailable
    case settingDidNotChange
}

private struct PMSetSleepSettings: TBClosedLidPowerSettingsStore {
    private let executable = URL(fileURLWithPath: TBClosedLidPowerPMSetCommand.executablePath)

    func readSleepDisabled() throws -> Bool {
        let output = try run(arguments: ["-g"])
        guard let value = TBClosedLidPowerPMSetCommand.parseSleepDisabled(output) else {
            throw HelperFailure.settingUnavailable
        }
        return value
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        _ = try run(arguments: TBClosedLidPowerPMSetCommand.setArguments(disabled: disabled))
    }

    private func run(arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw HelperFailure.settingUnavailable }
        return String(decoding: data, as: UTF8.self)
    }
}

private func currentBootSessionIdentifier() throws -> String {
    let key = "kern.bootsessionuuid"
    var size = 0
    guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 1 else {
        throw HelperFailure.invalidBootSession
    }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else {
        throw HelperFailure.invalidBootSession
    }
    let rawValueBytes = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    let rawValue = String(decoding: rawValueBytes, as: UTF8.self)
    let normalized = rawValue.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    guard TBClosedLidPowerTransaction.isValidSessionID(normalized) else { throw HelperFailure.invalidBootSession }
    return normalized
}

private func currentSigningTeamIdentifier() throws -> String {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
        throw HelperFailure.invalidIdentity
    }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
        throw HelperFailure.invalidIdentity
    }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let teamIdentifier = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
          TBClosedLidPowerHelperIdentity.signingRequirement(
            bundleIdentifier: TBClosedLidPowerHelperIdentity.clientBundleIdentifier,
            teamIdentifier: teamIdentifier
          ) != nil else {
        throw HelperFailure.invalidIdentity
    }
    return teamIdentifier
}

private final class HelperService: NSObject, NSXPCListenerDelegate, TBClosedLidPowerHelperProtocol, @unchecked Sendable {
    private let coordinator: TBClosedLidPowerSessionCoordinator
    private let bootSessionID: String
    private var watchdog: Timer?

    init(coordinator: TBClosedLidPowerSessionCoordinator, bootSessionID: String) {
        self.coordinator = coordinator
        self.bootSessionID = bootSessionID
    }

    func startWatchdog() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            do {
                _ = try self.coordinator.recover(
                    currentBootSessionID: self.bootSessionID,
                    uptime: ProcessInfo.processInfo.systemUptime
                )
            } catch {
                NSLog("Closed-lid helper recovery failed; retaining journal: %@", String(describing: error))
            }
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The listener's code-signing requirement is applied before activation.
        // Use the kernel-provided peer UID only after that signature gate.
        guard connection.effectiveUserIdentifier != 0 else { return false }
        connection.exportedInterface = NSXPCInterface(with: TBClosedLidPowerHelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { NSLog("Closed-lid helper client disconnected") }
        connection.resume()
        return true
    }

    func beginSession(identifier: String, withReply reply: @escaping (Bool, String?) -> Void) {
        guard let connection = NSXPCConnection.current(), connection.effectiveUserIdentifier != 0 else {
            reply(false, "unauthorized-client")
            return
        }
        do {
            try coordinator.begin(
                sessionID: identifier,
                bootSessionID: bootSessionID,
                ownerUID: UInt32(connection.effectiveUserIdentifier),
                uptime: ProcessInfo.processInfo.systemUptime
            )
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func heartbeat(identifier: String, withReply reply: @escaping (Bool, String?) -> Void) {
        guard let connection = NSXPCConnection.current(), connection.effectiveUserIdentifier != 0 else {
            reply(false, "unauthorized-client")
            return
        }
        do {
            try coordinator.heartbeat(
                sessionID: identifier,
                ownerUID: UInt32(connection.effectiveUserIdentifier),
                bootSessionID: bootSessionID,
                uptime: ProcessInfo.processInfo.systemUptime
            )
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func endSession(identifier: String, withReply reply: @escaping (Bool, String?) -> Void) {
        guard let connection = NSXPCConnection.current(), connection.effectiveUserIdentifier != 0 else {
            reply(false, "unauthorized-client")
            return
        }
        do {
            _ = try coordinator.end(
                sessionID: identifier,
                ownerUID: UInt32(connection.effectiveUserIdentifier),
                bootSessionID: bootSessionID,
                uptime: ProcessInfo.processInfo.systemUptime
            )
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func status(withReply reply: @escaping (String) -> Void) {
        guard let connection = NSXPCConnection.current(), connection.effectiveUserIdentifier != 0 else {
            reply("unavailable")
            return
        }
        do {
            let lease = try TBClosedLidPowerJournal(
                directoryURL: URL(fileURLWithPath: TBClosedLidPowerHelperIdentity.journalPath),
                expectedOwnerUID: 0
            ).read(currentBootSessionID: bootSessionID)
            reply(lease?.ownerUID == UInt32(connection.effectiveUserIdentifier) ? "active" : "inactive")
        } catch {
            reply("unavailable")
        }
    }
}

private func runHelper() throws -> Never {
    let teamID = try currentSigningTeamIdentifier()
    guard let requirement = TBClosedLidPowerHelperIdentity.signingRequirement(
        bundleIdentifier: TBClosedLidPowerHelperIdentity.clientBundleIdentifier,
        teamIdentifier: teamID
    ) else { throw HelperFailure.invalidIdentity }

    let bootSessionID = try currentBootSessionIdentifier()
    let settings = PMSetSleepSettings()
    let journal = TBClosedLidPowerJournal(
        directoryURL: URL(fileURLWithPath: TBClosedLidPowerHelperIdentity.journalPath, isDirectory: true),
        expectedOwnerUID: 0
    )
    let coordinator = TBClosedLidPowerSessionCoordinator(journal: journal, settings: settings)
    _ = try coordinator.recover(currentBootSessionID: bootSessionID, uptime: ProcessInfo.processInfo.systemUptime)

    let service = HelperService(coordinator: coordinator, bootSessionID: bootSessionID)
    service.startWatchdog()
    let listener = NSXPCListener(machServiceName: TBClosedLidPowerHelperIdentity.machServiceName)
    listener.delegate = service
    listener.setConnectionCodeSigningRequirement(requirement)
    listener.activate()
    RunLoop.current.run()
    fatalError("LaunchDaemon run loop exited unexpectedly")
}

do {
    try runHelper()
} catch {
    NSLog("Closed-lid helper refused to start: %@", String(describing: error))
    exit(EXIT_FAILURE)
}
