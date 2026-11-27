import Foundation
import IOKit
import IOKit.ps

struct TBClosedLidPowerSourceReading: Equatable {
    let source: TBClosedLidPowerSource
    let currentCapacity: Int?
    let maximumCapacity: Int?
}

struct TBClosedLidPowerSnapshot: Equatable {
    let source: TBClosedLidPowerSource
    let batteryPercent: Int?
    let thermalState: TBClosedLidPowerThermalState

    static let unavailable = TBClosedLidPowerSnapshot(
        source: .unknown,
        batteryPercent: nil,
        thermalState: .unsupported
    )
}

@MainActor
final class TBClosedLidPowerMonitor: ObservableObject {
    @Published private(set) var snapshot = TBClosedLidPowerSnapshot.unavailable

    private let notificationCenter: NotificationCenter
    private let powerSourceReader: () -> TBClosedLidPowerSourceReading
    private let thermalStateReader: () -> TBClosedLidPowerThermalState
    private var thermalObserver: NSObjectProtocol?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var isMonitoring = false

    init(
        notificationCenter: NotificationCenter = .default,
        powerSourceReader: (() -> TBClosedLidPowerSourceReading)? = nil,
        thermalStateReader: (() -> TBClosedLidPowerThermalState)? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.powerSourceReader = powerSourceReader ?? { Self.readPowerSource() }
        self.thermalStateReader = thermalStateReader ?? { Self.readThermalState() }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        thermalObserver = notificationCenter.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<TBClosedLidPowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak monitor] in monitor?.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source {
            powerSourceRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        refresh()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        if let thermalObserver {
            notificationCenter.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
            self.powerSourceRunLoopSource = nil
        }
    }

    func refresh() {
        let power = powerSourceReader()
        snapshot = TBClosedLidPowerSnapshot(
            source: power.source,
            batteryPercent: Self.batteryPercentage(
                current: power.currentCapacity,
                maximum: power.maximumCapacity
            ),
            thermalState: thermalStateReader()
        )
    }

    nonisolated static func batteryPercentage(current: Int?, maximum: Int?) -> Int? {
        guard let current, let maximum, maximum > 0, current >= 0, current <= maximum else {
            return nil
        }
        return Int((Double(current) / Double(maximum) * 100).rounded())
    }

    private static func readPowerSource() -> TBClosedLidPowerSourceReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .init(source: .unknown, currentCapacity: nil, maximumCapacity: nil)
        }
        let sourceType = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String?
        guard let sourceType else {
            return .init(source: .unknown, currentCapacity: nil, maximumCapacity: nil)
        }
        if sourceType == (kIOPSACPowerValue as String) {
            return .init(source: .ac, currentCapacity: nil, maximumCapacity: nil)
        }
        guard sourceType == (kIOPSBatteryPowerValue as String) else {
            return .init(source: .unknown, currentCapacity: nil, maximumCapacity: nil)
        }

        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let current = description[kIOPSCurrentCapacityKey as String] as? Int
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int
            return .init(source: .battery, currentCapacity: current, maximumCapacity: maximum)
        }
        return .init(source: .battery, currentCapacity: nil, maximumCapacity: nil)
    }

    private static func readThermalState() -> TBClosedLidPowerThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unsupported
        }
    }
}
