// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Your usual cycling speed (wish #30 "Import bike speed"), so bike routes and Bike & Ride plan at
/// your pace: from the cycling workouts in Apple Health (last 180 days, distance over time),
/// else from Apple Health's cycling speed samples. Read on the device only; only the speed is kept.
enum CyclingPace {
    static var isAvailable: Bool { WalkingPace.healthAvailable }

    /// Measures and stores the speed in m/s; nil without enough cycling or without access.
    @MainActor
    static func measure() async -> Double? {
        guard let v = await healthSpeed(), SmartRouting.cyclingSpeedRange.contains(v) else { return nil }
        UserDefaults.standard.set(v, forKey: SmartRouting.measuredCyclingSpeedKey)
        return v
    }

    @MainActor
    private static func healthSpeed() async -> Double? {
        #if canImport(HealthKit)
        guard WalkingPace.healthAvailable else { return nil }
        let store = HKHealthStore()
        let distance = HKQuantityType(.distanceCycling)
        let speed = HKQuantityType(.cyclingSpeed)
        let workouts = HKObjectType.workoutType()
        do { try await store.requestAuthorization(toShare: [], read: [workouts, distance, speed]) } catch { return nil }
        let end = Date()
        let since = HKQuery.predicateForSamples(withStart: end.addingTimeInterval(-180 * 86_400), end: end)
        let cycling = HKQuery.predicateForWorkouts(with: .cycling)
        let both = NSCompoundPredicate(andPredicateWithSubpredicates: [since, cycling])
        let query = HKSampleQueryDescriptor(predicates: [.workout(both)], sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                                            limit: 200)
        if let found = try? await query.result(for: store) {
            let rides: [(meters: Double, seconds: Double)] = found.compactMap { w in
                guard let m = w.statistics(for: distance)?.sumQuantity()?.doubleValue(for: .meter()) else { return nil }
                return (m, w.duration)
            }
            if let v = SmartRouting.cyclingSpeed(fromRides: rides) { return v }
        }
        let samples = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: speed, predicate: since), options: .discreteAverage)
        guard let stats = try? await samples.result(for: store), let avg = stats.averageQuantity() else { return nil }
        return avg.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
        #else
        return nil
        #endif
    }
}
