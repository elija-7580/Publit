import CoreMotion
import Foundation

/// Your usual walking speed from the iPhone's step counter (the last seven days), so smart
/// routing plans walks and changes at your pace. Read on the device only.
enum WalkingPace {
    static var isAvailable: Bool { CMPedometer.isDistanceAvailable() && CMPedometer.isStepCountingAvailable() }

    /// Measures and stores the speed in m/s; nil without enough walking or without access.
    @MainActor
    static func measure() async -> Double? {
        guard isAvailable else { return nil }
        let pedometer = CMPedometer()
        let end = Date()
        let start = end.addingTimeInterval(-7 * 86_400)
        let result: (pace: Double?, distance: Double?, steps: Double?) = await withCheckedContinuation { c in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                _ = pedometer
                c.resume(returning: (data?.averageActivePace?.doubleValue, data?.distance?.doubleValue, data?.numberOfSteps.doubleValue))
            }
        }
        var speed: Double?
        if let pace = result.pace, pace > 0 { speed = 1 / pace }
        // No pace in the history: step length at a usual walking cadence (about 1.8 steps a second).
        if speed == nil, let d = result.distance, let s = result.steps, s > 2_000 { speed = d / s * 1.8 }
        guard let speed, (0.6...2.2).contains(speed) else { return nil }
        UserDefaults.standard.set(speed, forKey: SmartRouting.measuredSpeedKey)
        return speed
    }
}
