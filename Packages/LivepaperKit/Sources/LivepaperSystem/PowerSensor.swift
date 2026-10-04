import Foundation
import IOKit.ps
import LivepaperCore

/// How the Mac is powered, as far as the pause rules care.
nonisolated public struct PowerState: Equatable, Sendable {
    public var lowPowerMode: Bool
    public var onBattery: Bool

    public init(lowPowerMode: Bool = false, onBattery: Bool = false) {
        self.lowPowerMode = lowPowerMode
        self.onBattery = onBattery
    }
}

/// Low Power Mode and the power source.
public protocol PowerSensor: AnyObject {
    /// The power state now, and again each time it changes.
    func updates() -> AsyncStream<PowerState>
}

/// Reads Low Power Mode from `ProcessInfo` and the power source from IOKit,
/// again when either says it changed.
public final class SystemPowerSensor: PowerSensor {
    private let broadcast = Broadcast<PowerState>()
    private var lowPowerObserver: (any NSObjectProtocol)?
    private var sourceObservation: DarwinObservation?

    public init() {
        broadcast.whenRead(start: { [weak self] in self?.start() }, stop: { [weak self] in self?.stop() })
    }

    public func updates() -> AsyncStream<PowerState> {
        broadcast.stream()
    }

    private func start() {
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        sourceObservation = DarwinNotification(kIOPSNotifyPowerSource).observe(on: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        broadcast.send(Self.current())
    }

    private func stop() {
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
        sourceObservation?.cancel()
        sourceObservation = nil
    }

    private func changed() {
        let state = Self.current()
        if state != broadcast.latest { broadcast.send(state) }
    }

    static func current() -> PowerState {
        PowerState(lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, onBattery: onBattery())
    }

    private static func onBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return source as String == kIOPSBatteryPowerValue
    }
}
