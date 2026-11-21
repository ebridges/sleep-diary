import Foundation
import HealthKit
import SwiftData
import Observation

/// The four steps of the morning check-in, in order.
enum CheckInStep: Int, CaseIterable, Identifiable, Hashable {
    case morning, lastNight, yesterday, medication
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .medication: return "Medication"
        case .lastNight: return "Last night"
        case .yesterday: return "Yesterday"
        case .morning: return "This morning"
        }
    }

    var detail: String {
        switch self {
        case .medication: return "Confirm your evening dose from Health"
        case .lastNight: return "Confirm sleep, wake-ups and wake time"
        case .yesterday: return "Caffeine, alcohol and naps"
        case .morning: return "How rested and how groggy"
        }
    }

    var systemImage: String {
        switch self {
        case .medication: return "pills"
        case .lastNight: return "moon"
        case .yesterday: return "cup.and.saucer"
        case .morning: return "sun.max"
        }
    }
}

enum CheckInRoute: Hashable {
    case step(CheckInStep)
    case saved
    case history
    case daytime
}

/// One night's check-in: the draft every step edits, what Health recorded,
/// and saving each step to the diary entry.
@MainActor
@Observable
final class CheckIn {
    var d: EntryDraft
    private(set) var entry: DiaryEntry?

    var summaries: [NightSleepSummary] = []
    var sleepLoading = true
    var sleepError: String?
    /// Health said it hasn't been asked for access yet (the permission sheet never completed).
    var needsHealthAccess = false

    /// Per medication name: what Health logged that evening, and its usual dose and time.
    var medicationLookups: [String: MedicationLookup] = [:]
    var medicationRoutines: [String: MedicationRoutine] = [:]
    /// The names the lookups above were made for.
    var medicationsLookedUp: [String]?
    /// The previous night's medication records, for each medication's last dose and time.
    let previousMedications: [MedicationRecord]
    var healthCaffeineLoaded = false

    /// What the last save wrote to Health, for the Saved screen.
    var healthLines: [HealthWriteLine] = []
    var healthError: String?

    private let context: ModelContext
    private let health: HealthManager

    init(night: Date, entries: [DiaryEntry], context: ModelContext, health: HealthManager, defaultMedicationName: String) {
        self.context = context
        self.health = health
        let existing = entries.first { Calendar.current.isDate($0.night, inSameDayAs: night) }
        entry = existing
        previousMedications = entries.first { $0.night < night }?.draft.medications ?? []
        if let existing {
            d = existing.draft
        } else {
            let previous = entries.first { $0.night < night }?.draft
            d = EntryDraft.new(after: previous, defaultMedicationName: defaultMedicationName)
            d.night = Calendar.current.startOfDay(for: night)
            d.reanchor()
        }
    }

    var night: Date { d.night }

    var current: NightSleepSummary? {
        summaries.first { $0.sourceID == d.healthSourceID } ?? summaries.first
    }

    // MARK: Step state

    func isDone(_ step: CheckInStep) -> Bool { confirmedAt(step) != nil }

    var allDone: Bool { CheckInStep.allCases.allSatisfy(isDone) }

    /// The first step not yet confirmed, if any.
    var nextOpenStep: CheckInStep? { CheckInStep.allCases.first { !isDone($0) } }

    /// Where to go after finishing `step`: the next unconfirmed step after it,
    /// else any unconfirmed step, else the Saved screen.
    func route(after step: CheckInStep) -> CheckInRoute {
        let later = CheckInStep.allCases.filter { $0.rawValue > step.rawValue && !isDone($0) }
        if let next = later.first ?? nextOpenStep { return .step(next) }
        return .saved
    }

    private func confirmedAt(_ step: CheckInStep) -> Date? {
        guard let entry else { return nil }
        switch step {
        case .medication: return entry.medicationConfirmedAt
        case .lastNight: return entry.lastNightConfirmedAt
        case .yesterday: return entry.yesterdayConfirmedAt
        case .morning: return entry.morningConfirmedAt
        }
    }

    // MARK: Loading

    func loadSleep(preferredSource: String) async {
        sleepLoading = true
        defer { sleepLoading = false }
        do {
            summaries = try await health.sleepSummaries(forNight: night)
            sleepError = nil
            needsHealthAccess = false
        } catch {
            summaries = []
            needsHealthAccess = (error as? HKError)?.code == .errorAuthorizationNotDetermined
            sleepError = "Couldn't read Health: \(error.localizedDescription)"
        }
        if !summaries.contains(where: { $0.sourceID == d.healthSourceID }) {
            d.healthSourceID = NightSleepSummary.pick(from: summaries, preferred: preferredSource)?.sourceID ?? ""
        }
        if !isDone(.lastNight), let s = current { prefillNight(from: s) }
    }

    /// Asks for Health access again and reloads the night.
    func requestHealthAccess(preferredSource: String) async -> HealthAccessResult {
        let result = await health.requestAuthorization()
        await loadSleep(preferredSource: preferredSource)
        return result
    }

    /// Switching source re-reads its times (unless already confirmed) and clears
    /// remembered wake-ups, which belong to the previous source's recording.
    func selectSource(_ id: String) {
        guard id != d.healthSourceID else { return }
        d.healthSourceID = id
        d.rememberedWakes = []
        if !isDone(.lastNight), let s = current { prefillNight(from: s) }
    }

    private func prefillNight(from s: NightSleepSummary) {
        if let onset = s.sleepOnset {
            d.sleepOnset = onset
            d.bedTime = s.inBedSpanStart ?? onset
        }
        if let wake = s.finalWake { d.finalWake = wake }
    }

    func loadMedications(_ names: [String]) async {
        var lookups: [String: MedicationLookup] = [:]
        var routines: [String: MedicationRoutine] = [:]
        for name in names {
            lookups[name] = await health.eveningDose(forNight: night, matching: name)
            routines[name] = await health.medicationRoutine(matching: name)
        }
        // A newer lookup (the list changed in Settings) replaces this one.
        guard !Task.isCancelled else { return }
        medicationLookups = lookups
        medicationRoutines = routines
        medicationsLookedUp = names
    }


    /// Adds caffeine other apps logged for the day, once per check-in.
    func loadHealthCaffeine() async {
        guard !healthCaffeineLoaded else { return }
        healthCaffeineLoaded = true
        let start = TimeResolver.at(hour: 4, minute: 0, night: night, anchor: .daytime)
        let end = max(start, d.sleepOnset)
        guard let items = try? await health.caffeineFromOtherApps(from: start, to: end) else { return }
        let known = Set(d.caffeine.filter(\.isFromHealth).map { "\($0.time.timeIntervalSince1970)-\($0.mg)" })
        let fresh = items.filter { !known.contains("\($0.time.timeIntervalSince1970)-\($0.mg)") }
        d.caffeine.append(contentsOf: fresh)
        d.caffeine.sort { $0.time < $1.time }
    }

    // MARK: Saving

    /// Saves the draft, marks `step` confirmed and rewrites this entry's Health samples.
    func confirm(_ step: CheckInStep, writeNaps: Bool) async {
        if step == .lastNight { updateWakeTotals() }

        let target: DiaryEntry
        if let entry {
            entry.apply(d)
            target = entry
        } else {
            target = DiaryEntry(draft: d)
            context.insert(target)
            entry = target
        }
        let now = Date()
        switch step {
        case .medication: target.medicationConfirmedAt = now
        case .lastNight: target.lastNightConfirmedAt = now
        case .yesterday: target.yesterdayConfirmedAt = now
        case .morning: target.morningConfirmedAt = now
        }
        try? context.save()

        do {
            healthLines = try await health.sync(d, entryID: target.entryID, writeNaps: writeNaps,
                                                writeGrogginess: target.morningConfirmedAt != nil)
            healthError = nil
            target.healthSyncedAt = Date()
            target.healthSyncError = nil
        } catch {
            healthLines = []
            healthError = error.localizedDescription
            target.healthSyncError = error.localizedDescription
        }
        try? context.save()
    }

    /// The diary's own count: wake-ups the user remembers plus ones they added.
    private func updateWakeTotals() {
        let remembered = (current?.wakes ?? []).filter(isRemembered)
        d.rememberedWakes = remembered.map(\.start)
        d.healthSourceID = current?.sourceID ?? ""
        d.awakenings = remembered.count + d.addedWakes.count
        let rememberedMinutes = remembered.reduce(0.0) { $0 + $1.duration } / 60
        d.minutesAwake = Int(rememberedMinutes.rounded()) + d.addedWakes.reduce(0) { $0 + $1.minutes }
    }

    func isRemembered(_ wake: DateInterval) -> Bool {
        d.rememberedWakes.contains { abs($0.timeIntervalSince(wake.start)) < 60 }
    }

    func toggleRemembered(_ wake: DateInterval) {
        if isRemembered(wake) {
            d.rememberedWakes.removeAll { abs($0.timeIntervalSince(wake.start)) < 60 }
        } else {
            d.rememberedWakes.append(wake.start)
        }
    }
}
