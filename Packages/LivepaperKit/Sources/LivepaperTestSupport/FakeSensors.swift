import LivepaperCore
import LivepaperSystem

/// A sensor that reports whatever it is told to, to every stream made from it.
///
/// One generic fake stands in for every sensor; the names below say which. The
/// covered displays' has one of its own, which also keeps what it was told.
@MainActor
public final class FakeSensor<Value: Sendable> {
    private let broadcast: Broadcast<Value>

    /// A sensor of a state, which starts at `initial` and gives each new stream the latest value.
    public init(_ initial: Value) {
        broadcast = Broadcast()
        broadcast.send(initial)
    }

    /// A sensor of events, which gives a new stream only what happens after it is made.
    public init() {
        broadcast = Broadcast(replaysLatest: false, bufferingPolicy: .unbounded)
    }

    public func updates() -> AsyncStream<Value> {
        broadcast.stream()
    }

    /// Reports a value, as the system would.
    public func send(_ value: Value) {
        broadcast.send(value)
    }

    public var latest: Value? { broadcast.latest }

    /// How many streams are being read: a sensor with none observes nothing.
    public var readerCount: Int { broadcast.readerCount }
}

public typealias FakeDisplaySensor = FakeSensor<[ConnectedDisplay]>
public typealias FakePowerSensor = FakeSensor<PowerState>
public typealias FakeLockSensor = FakeSensor<Bool>
public typealias FakeSleepSensor = FakeSensor<SystemSleepEvent>
public typealias FakeDisplaySleepSensor = FakeSensor<Set<DisplayIdentity>>

extension FakeSensor: DisplaySensor where Value == [ConnectedDisplay] {}
extension FakeSensor: PowerSensor where Value == PowerState {}
extension FakeSensor: LockSensor where Value == Bool {}
extension FakeSensor: SleepSensor where Value == SystemSleepEvent {}
extension FakeSensor: DisplaySleepSensor where Value == Set<DisplayIdentity> {}

/// A covered-display sensor that reports whatever it is told to, and keeps
/// whether it was told that covering pauses the wallpaper.
@MainActor
public final class FakeCoveredDisplaySensor: CoveredDisplaySensor {
    private let sensor: FakeSensor<Set<DisplayIdentity>>
    public var coveringPauses = false

    public init(_ initial: Set<DisplayIdentity>) {
        sensor = FakeSensor(initial)
    }

    public func updates() -> AsyncStream<Set<DisplayIdentity>> {
        sensor.updates()
    }

    /// Reports the covered displays, as the system would.
    public func send(_ covered: Set<DisplayIdentity>) {
        sensor.send(covered)
    }

    public var latest: Set<DisplayIdentity>? { sensor.latest }

    /// How many streams are being read: a sensor with none observes nothing.
    public var readerCount: Int { sensor.readerCount }
}
