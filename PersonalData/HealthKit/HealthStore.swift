import Foundation
import HealthKit

/// Thin wrapper around HKHealthStore for the few queries the dashboard needs.
final class HealthStore {
    static let shared = HealthStore()
    let store = HKHealthStore()

    static let readTypes: Set<HKObjectType> = {
        var s: Set<HKObjectType> = []
        let q: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRate, .vo2Max, .bodyMass,
            .bloodPressureSystolic, .bloodPressureDiastolic,
            .stepCount, .appleExerciseTime, .activeEnergyBurned,
            .heartRateVariabilitySDNN,
        ]
        for id in q { if let t = HKQuantityType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }()

    func authorize() async throws {
        try await store.requestAuthorization(toShare: [], read: HealthStore.readTypes)
    }

    /// Latest single value of a quantity type within the last `hours`.
    /// Returns the value in the supplied unit.
    func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit, hours: Int = 36) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let start = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        let pred = HKQuery.predicateForSamples(
            withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: pred,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                if let q = (samples?.first as? HKQuantitySample) {
                    cont.resume(returning: q.quantity.doubleValue(for: unit))
                } else {
                    cont.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }

    /// Total minutes of asleep-state in the past `hours`.
    func sleepMinutes(hours: Int = 36) async -> Double? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        let pred = HKQuery.predicateForSamples(
            withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let cats = samples as? [HKCategorySample] else {
                    cont.resume(returning: nil); return
                }
                let asleep = cats.filter { $0.value != HKCategoryValueSleepAnalysis.awake.rawValue }
                let total = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: total / 60.0)
            }
            store.execute(query)
        }
    }
}
