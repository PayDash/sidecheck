import UserNotifications
import IOKit.ps

// MARK: - Shared battery read

/// IOKit battery snapshot shared by StatsStore and the alerter.
enum BatteryInfo {
    struct Snapshot: Equatable {
        let percent: Int
        let isCharging: Bool
    }

    /// nil on desktop Macs without a battery.
    static func current() -> Snapshot? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return Snapshot(
                percent: Int((Double(current) / Double(max) * 100).rounded()),
                isCharging: (description[kIOPSIsChargingKey] as? Bool) ?? false
            )
        }
        return nil
    }
}

// MARK: - Low-battery alerts

/// Posts a macOS notification when the battery drops through 20% / 10% while
/// on battery power. Runs its own slow timer so alerts work while the panel
/// is closed. Enabling the toggle asks for notification permission once; a
/// denial reverts the toggle.
@MainActor
final class BatteryAlerter: ObservableObject {
    static let enabledKey = "lowBatteryAlertsEnabled"
    private static let thresholds: [Int] = [20, 10]
    private static let pollInterval: TimeInterval = 30

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { requestAuthorizationThenStart() } else { stop() }
        }
    }

    private var timer: Timer?
    private var firedThresholds: Set<Int> = []

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        // didSet doesn't fire during init — start manually. A persisted
        // `true` implies permission was granted when the toggle went on.
        if isEnabled { start() }
    }

    private func requestAuthorizationThenStart() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if granted {
                    self.start()
                } else {
                    self.isEnabled = false // denied — revert the toggle (didSet stops the timer)
                }
            }
        }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        firedThresholds = []
    }

    private func check() {
        guard let battery = BatteryInfo.current() else { return }
        if battery.isCharging || battery.percent > Self.thresholds.max()! + 5 {
            firedThresholds.removeAll() // fresh charge cycle — thresholds can fire again
            return
        }
        for threshold in Self.thresholds where battery.percent <= threshold && !firedThresholds.contains(threshold) {
            firedThresholds.insert(threshold)
            post(title: "Battery at \(battery.percent)%", body: "Sidecheck noticed — maybe plug in soon.")
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "sidecheck.battery.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
