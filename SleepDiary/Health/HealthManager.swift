import Foundation
import HealthKit
import Observation

/// An evening dose of the user's medication, read from Health's Medications.
struct MedicationDose: Equatable {
    let name: String
    /// e.g. "1 tablet"
    let amount: String
    let time: Date
}

enum MedicationLookup: Equatable {
    case found(MedicationDose)
    /// The medication is shared with the app but has no dose logged as taken that evening.
    case noDose
    /// No shared medication matches the name (or the user hasn't shared any).
    case notShared
    /// Medications need iOS 26.
    case unsupported
    /// No medication is set in Settings, so there's nothing to look for.
    case notSet
}

/// What happened when the app asked for Health access.
enum HealthAccessResult: Equatable {
    /// iOS showed the permission sheet.
    case asked
    /// iOS had an answer already, so it showed nothing. Changes go through the Health app.
    case alreadyAnswered
    case unavailable
    case failed(String)
}

/// One line of "what was written to Apple Health" for the Saved screen.
struct HealthWriteLine: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { label }
}

/// Everything that touches Apple Health lives here.
///
/// Writes: caffeine, alcoholic drinks, fatigue and dizziness symptoms, and
/// (optional) naps. Every sample is tagged with the diary entry's ID so
/// editing or deleting an entry replaces what it wrote. The user's
/// corrections to the night are never written.
///
/// Reads: sleep analysis and caffeine from every other source, and medication
/// dose events (iOS 26).
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
    static let headacheType = HKCategoryType(.headache)

    static var writeTypes: Set<HKSampleType> {
        [sleepType, caffeineType, alcoholType, fatigueType, dizzinessType, headacheType]
    }
    static var readTypes: Set<HKObjectType> {
        [sleepType, caffeineType, alcoholType]
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var skipAuthorization: Bool {
        #if DEBUG
        // For UI checks in the Simulator, where the permission sheet can come up blank.
        return ProcessInfo.processInfo.arguments.contains("-SkipHealthAuth")
        #else
        return false
        #endif
    }

    @discardableResult
    func requestAuthorization() async -> HealthAccessResult {
        guard isAvailable else { return .unavailable }
        guard !skipAuthorization else { return .alreadyAnswered }
        let status = try? await store.statusForAuthorizationRequest(toShare: Self.writeTypes, read: Self.readTypes)
        do {
            try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
            lastError = nil
            return status == .unnecessary ? .alreadyAnswered : .asked
        } catch {
            lastError = error.localizedDescription
            print("Sleep Diary: Health authorization failed: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    /// Shows Health's sheet for choosing which medications the app may read.
    /// It appears every time this is called, so only call it when the user asks.
    func requestMedicationAccess() async {
        guard isAvailable, !skipAuthorization else { return }
        guard #available(iOS 26.0, *) else { return }
        do {
            try await store.requestPerObjectReadAuthorization(for: .userAnnotatedMedicationType(), predicate: nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func canWrite(_ type: HKObjectType) -> Bool {
        store.authorizationStatus(for: type) == .sharingAuthorized
    }

    // MARK: Writing

    /// Replaces everything written for this entry. Returns what was written,
    /// for the Saved screen.
    @discardableResult
    func sync(_ d: EntryDraft, entryID: UUID, writeNaps: Bool, writeGrogginess: Bool) async throws -> [HealthWriteLine] {
        guard isAvailable else { return [HealthWriteLine(label: "Apple Health", value: "Not available")] }
        try await deleteSamples(for: entryID)

        let meta: [String: Any] = [
            HKMetadataKeyExternalUUID: entryID.uuidString,
            HKMetadataKeyWasUserEntered: true,
        ]
        var objects: [HKObject] = []
        var lines: [HealthWriteLine] = []
        let notAllowed = "Not allowed"

        if writeGrogginess {
            if canWrite(Self.fatigueType) {
                objects.append(HKCategorySample(type: Self.fatigueType, value: severityValue(d.grogginess),
                                                start: d.finalWake, end: d.finalWake, metadata: meta))
                lines.append(.init(label: "Fatigue (grogginess)", value: "\(d.grogginess.label), \(Fmt.time(d.finalWake))"))
            } else {
                lines.append(.init(label: "Fatigue (grogginess)", value: notAllowed))
            }
        }

        let caffeine = d.ownCaffeine.filter { $0.mg > 0 }
        if !caffeine.isEmpty {
            if canWrite(Self.caffeineType) {
                for c in caffeine {
                    let q = HKQuantity(unit: .gramUnit(with: .milli), doubleValue: c.mg)
                    objects.append(HKQuantitySample(type: Self.caffeineType, quantity: q,
                                                    start: c.time, end: c.time, metadata: meta))
                }
                let mg = Int(caffeine.reduce(0) { $0 + $1.mg })
                lines.append(.init(label: "Caffeine", value: "\(caffeine.count) item\(caffeine.count == 1 ? "" : "s"), \(mg) mg"))
            } else {
                lines.append(.init(label: "Caffeine", value: notAllowed))
            }
        }

        let alcohol = d.alcohol.filter { $0.drinks > 0 }
        if !alcohol.isEmpty {
            if canWrite(Self.alcoholType) {
                for a in alcohol {
                    let q = HKQuantity(unit: .count(), doubleValue: a.drinks)
                    objects.append(HKQuantitySample(type: Self.alcoholType, quantity: q,
                                                    start: a.time, end: a.time, metadata: meta))
                }
                let n = alcohol.reduce(0) { $0 + $1.drinks }
                lines.append(.init(label: "Alcoholic drinks", value: Fmt.number(n)))
            } else {
                lines.append(.init(label: "Alcoholic drinks", value: notAllowed))
            }
        }

        // Night times are the user's corrections and stay in the app; only naps
        // are written as sleep.
        let naps = d.naps.filter { $0.minutes > 0 }
        if !naps.isEmpty {
            if !writeNaps {
                lines.append(.init(label: "Naps", value: "Off in Settings"))
            } else if canWrite(Self.sleepType) {
                for n in naps {
                    objects.append(HKCategorySample(
                        type: Self.sleepType,
                        value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                        start: n.start, end: n.end, metadata: meta))
                }
                lines.append(.init(label: "Naps", value: "\(naps.count) as sleep"))
            } else {
                lines.append(.init(label: "Naps", value: notAllowed))
            }
        }

        // From the v1 editor: day-long symptoms on the night's entry.
        let dayStart = d.finalWake
        let dayEnd = d.finalWake.addingTimeInterval(12 * 3600)
        if d.daytimeSleepiness != .notPresent && canWrite(Self.fatigueType) {
            objects.append(HKCategorySample(type: Self.fatigueType, value: severityValue(d.daytimeSleepiness),
                                            start: dayStart, end: dayEnd, metadata: meta))
        }
        if d.dizziness != .notPresent && canWrite(Self.dizzinessType) {
            objects.append(HKCategorySample(type: Self.dizzinessType, value: severityValue(d.dizziness),
                                            start: dayStart, end: dayEnd, metadata: meta))
        }

        if !objects.isEmpty {
            try await store.save(objects)
        }
        return lines
    }

    /// Writes one daytime symptom, replacing whatever was written for it before.
    /// Returns a short description of what happened, for the UI.
    @discardableResult
    func sync(_ symptom: SymptomEntry) async throws -> String {
        guard isAvailable else { return "Apple Health isn't available" }
        try await deleteSamples(for: symptom.entryID)
        guard let type = symptom.kind.healthType, let name = symptom.kind.healthName else {
            return "Kept in Sleep Diary (Health has no type for it)"
        }
        guard canWrite(type) else { return "Not allowed in Health settings" }
        let meta: [String: Any] = [
            HKMetadataKeyExternalUUID: symptom.entryID.uuidString,
            HKMetadataKeyWasUserEntered: true,
        ]
        let sample = HKCategorySample(type: type, value: severityValue(symptom.severity),
                                      start: symptom.time, end: symptom.time, metadata: meta)
        try await store.save(sample)
        return "Saved to Health as \(name)"
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

    private func severityValue(_ s: Severity) -> Int {
        switch s {
        case .notPresent: return HKCategoryValueSeverity.notPresent.rawValue
        case .mild: return HKCategoryValueSeverity.mild.rawValue
        case .moderate: return HKCategoryValueSeverity.moderate.rawValue
        case .severe: return HKCategoryValueSeverity.severe.rawValue
        }
    }

    // MARK: Reading sleep

    /// Sleep recorded by other apps between 6 pm on `night` and 2 pm the next day,
    /// summarised per source.
    func sleepSummaries(forNight night: Date) async throws -> [NightSleepSummary] {
        #if DEBUG && targetEnvironment(simulator)
        let real = (try? await healthSleepSummaries(forNight: night)) ?? []
        return real.isEmpty ? SampleNight.summaries(forNight: night) : real
        #else
        return try await healthSleepSummaries(forNight: night)
        #endif
    }

    private func healthSleepSummaries(forNight night: Date) async throws -> [NightSleepSummary] {
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

    // MARK: Reading caffeine

    /// Caffeine other apps logged between `start` and `end`.
    func caffeineFromOtherApps(from start: Date, to end: Date) async throws -> [CaffeineItem] {
        guard isAvailable, end > start else { return [] }
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.caffeineType, predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let myBundle = Bundle.main.bundleIdentifier
        return try await descriptor.result(for: store)
            .filter { $0.sourceRevision.source.bundleIdentifier != myBundle }
            .map {
                CaffeineItem(time: $0.startDate, label: $0.sourceRevision.source.name,
                             mg: $0.quantity.doubleValue(for: .gramUnit(with: .milli)), fromHealth: true)
            }
    }

    // MARK: Reading medication

    /// The dose of `name` logged as taken between 4 pm on `night` and 4 am after it.
    func eveningDose(forNight night: Date, matching name: String) async -> MedicationLookup {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return .notSet }
        #if DEBUG && targetEnvironment(simulator)
        return SampleNight.dose(forNight: night, name: name)
        #else
        guard isAvailable else { return .notShared }
        guard #available(iOS 26.0, *) else { return .unsupported }
        do {
            return try await readEveningDose(forNight: night, matching: name)
        } catch {
            lastError = error.localizedDescription
            return .notShared
        }
        #endif
    }

    @available(iOS 26.0, *)
    private func readEveningDose(forNight night: Date, matching name: String) async throws -> MedicationLookup {
        let want = name.trimmingCharacters(in: .whitespaces)
        let meds = try await HKUserAnnotatedMedicationQueryDescriptor().result(for: store)
        let match = meds.first { m in
            m.medication.displayText.localizedCaseInsensitiveContains(want)
                || (m.nickname?.localizedCaseInsensitiveContains(want) ?? false)
        }
        guard let med = match else { return .notShared }

        let base = Calendar.current.startOfDay(for: night)
        let start = base.addingTimeInterval(16 * 3600)
        let end = base.addingTimeInterval(28 * 3600)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: []),
            HKQuery.predicateForMedicationDoseEvent(medicationConceptIdentifier: med.medication.identifier),
            HKQuery.predicateForMedicationDoseEvent(status: .taken),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKObjectType.medicationDoseEventType(), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let event = try await descriptor.result(for: store).first as? HKMedicationDoseEvent else {
            return .noDose
        }
        let displayName = med.nickname ?? med.medication.displayText
        return .found(MedicationDose(name: displayName,
                                     amount: Self.amountText(event.doseQuantity, form: med.medication.generalForm),
                                     time: event.startDate))
    }

    @available(iOS 26.0, *)
    private static func amountText(_ quantity: Double?, form: HKMedicationGeneralForm) -> String {
        let n = quantity ?? 1
        let noun: String
        switch form {
        case .tablet: noun = "tablet"
        case .capsule: noun = "capsule"
        default: noun = "dose"
        }
        return "\(Fmt.number(n)) \(noun)\(n == 1 ? "" : "s")"
    }
}
