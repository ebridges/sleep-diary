import Foundation
import HealthKit
import Observation

/// Everything that touches Apple Health lives here.
///
/// Writes: caffeine, alcoholic drinks, fatigue and dizziness symptoms, and
/// (optional) in-bed time plus naps. Every sample is tagged with the diary
/// entry's ID so editing or deleting an entry replaces what it wrote.
///
/// Reads: sleep analysis from every other source (Apple Watch, AutoSleep, …).
@MainActor
@Observable
final class HealthManager {
    let store = HKHealthStore()
    var lastError: String?

    static let sleepType = HKCategoryType(.sleepAnalysis)
    static let caffeineType = HKQuantityType(.dietaryCaffeine)
    static let alcoholType = HKQuantityType(.numberOfAlcoholicBeverages)
    static let fatigueType = HKCategoryType(.fatigue)
    static let dizzinessType = HKCategoryType(.dizziness)

    static var writeTypes: Set<HKSampleType> {
        [sleepType, caffeineType, alcoholType, fatigueType, dizzinessType]
    }
    static var readTypes: Set<HKObjectType> {
        [sleepType, caffeineType, alcoholType]
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func canWrite(_ type: HKObjectType) -> Bool {
        store.authorizationStatus(for: type) == .sharingAuthorized
    }

    // MARK: Writing

    func sync(_ d: EntryDraft, entryID: UUID, writeSleep: Bool) async throws {
        guard isAvailable else { return }
        try await deleteSamples(for: entryID)

        let meta: [String: Any] = [
            HKMetadataKeyExternalUUID: entryID.uuidString,
            HKMetadataKeyWasUserEntered: true,
        ]
        var objects: [HKObject] = []

        if canWrite(Self.caffeineType) {
            for c in d.caffeine where c.mg > 0 {
                let q = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: c.mg)
                objects.append(HKQuantitySample(type: Self.caffeineType, quantity: q,
                                                start: c.time, end: c.time, metadata: meta))
            }
        }

        if canWrite(Self.alcoholType) {
            for a in d.alcohol where a.drinks > 0 {
                let q = HKQuantity(unit: .count(), doubleValue: a.drinks)
                objects.append(HKQuantitySample(type: Self.alcoholType, quantity: q,
                                                start: a.time, end: a.time, metadata: meta))
            }
        }

        if writeSleep && canWrite(Self.sleepType) {
            if d.finalWake > d.bedTime {
                objects.append(HKCategorySample(
                    type: Self.sleepType,
                    value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                    start: d.bedTime, end: d.finalWake, metadata: meta))
            }
            for n in d.naps where n.minutes > 0 {
                objects.append(HKCategorySample(
                    type: Self.sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    start: n.start, end: n.end, metadata: meta))
            }
        }

        // Symptoms cover the day after the night: from final wake, 12 hours.
        let dayStart = d.finalWake
        let dayEnd = d.finalWake.addingTimeInterval(12 * 3600)
        let fatigue = max(d.grogginess.rawValue, d.daytimeSleepiness.rawValue)
        if fatigue > 0 && canWrite(Self.fatigueType) {
            objects.append(HKCategorySample(type: Self.fatigueType, value: severityValue(fatigue),
                                            start: dayStart, end: dayEnd, metadata: meta))
        }
        if d.dizziness.rawValue > 0 && canWrite(Self.dizzinessType) {
            objects.append(HKCategorySample(type: Self.dizzinessType,
                                            value: severityValue(d.dizziness.rawValue),
                                            start: dayStart, end: dayEnd, metadata: meta))
        }

        if !objects.isEmpty {
            try await store.save(objects)
        }
    }

    /// Removes everything this app wrote for one diary entry.
    func deleteSamples(for entryID: UUID) async throws {
        guard isAvailable else { return }
        let byEntry = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                                  allowedValues: [entryID.uuidString])
        let mine = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [byEntry, mine])

        for type in Self.writeTypes where canWrite(type) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                    if let error, (error as? HKError)?.code != .errorNoData {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
        }
    }

    private func severityValue(_ level: Int) -> Int {
        switch level {
        case 1: return HKCategoryValueSeverity.mild.rawValue
        case 2: return HKCategoryValueSeverity.moderate.rawValue
        default: return HKCategoryValueSeverity.severe.rawValue
        }
    }

    // MARK: Reading

    /// Sleep recorded by other apps between 6 pm on `night` and 2 pm the next day,
    /// summarised per source.
    func sleepSummaries(forNight night: Date) async throws -> [NightSleepSummary] {
        guard isAvailable else { return [] }
        let cal = Calendar.current
        let base = cal.startOfDay(for: night)
        guard let start = cal.date(byAdding: .hour, value: 18, to: base),
              let end = cal.date(byAdding: .hour, value: 38, to: base) else { return [] }

        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: Self.sleepType, predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        let myBundle = Bundle.main.bundleIdentifier
        let others = samples.filter { $0.sourceRevision.source.bundleIdentifier != myBundle }
        return NightSleepSummary.summarize(others)
    }
}
