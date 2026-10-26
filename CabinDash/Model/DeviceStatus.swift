import Foundation
import Network
import Observation
import UIKit

/// How the iPhone is connected, as far as iOS will say. It cannot say how strong a cellular signal is.
enum Connectivity: Equatable {
    case wifi
    case cellular
    case offline
    case other

    var symbol: String {
        switch self {
        case .wifi: return "wifi"
        // Not "cellularbars": that icon shows full bars whatever the signal, and iOS never says how strong it is.
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .offline: return "wifi.slash"
        case .other: return "network"
        }
    }
}

/// What the status rail shows besides the clock: connection and battery.
@MainActor @Observable
final class DeviceStatus {
    private(set) var connectivity: Connectivity = .other

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        monitor.pathUpdateHandler = { [weak self] path in
            let value: Connectivity
            if path.status != .satisfied {
                value = .offline
            } else if path.usesInterfaceType(.wifi) {
                value = .wifi
            } else if path.usesInterfaceType(.cellular) {
                value = .cellular
            } else {
                value = .other
            }
            Task { @MainActor in
                self?.connectivity = value
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.cabindash.network"))
    }

    /// 0...1, or nil when iOS does not know (for example on a simulator).
    var batteryLevel: Double? {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Double(level)
    }

    var isCharging: Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }
}
