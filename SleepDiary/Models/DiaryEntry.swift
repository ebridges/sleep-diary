import Foundation
import SwiftData

// MARK: - Small value types stored inside an entry

struct CaffeineItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Date
    var label: String
    var mg: Double
    /// Read from another app's Health sample; never written back.
    var fromHealth: Bool? = nil
    var isFromHealth: Bool { fromHealth == true }
}

struct AlcoholItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Date
    var drinks: Double
    /// Beer, Wine or Spirits.
    var kind: String? = nil
}

struct NapItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var minutes: Int
    var end: Date { start.addingTimeInterval(Double(minutes) * 60) }
}

enum Severity: Int, Codable, CaseIterable, Identifiable {
    case notPresent = 0, mild, moderate, severe
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .notPresent: return "Not present"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }
}

/// How falling asleep compared with what Health recorded.
enum FallAsleepFeel: String, Codable, CaseIterable, Identifiable {
    case aboutRight, tookLonger, notSure
    var id: String { rawValue }
    var label: String {
        switch self {
        case .aboutRight: return "About right"
        case .tookLonger: return "Took longer"
        case .notSure: return "Not sure"
        }
    }
}

/// A wake-up the user remembers that Health didn't record.
struct AddedWake: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var minutes: Int
}

struct CaffeinePreset: Identifiable {
    let name: String
    let mg: Double
    var id: String { name }

    static let all: [CaffeinePreset] = [
        .init(name: "Coffee", mg: 95),
        .init(name: "Espresso", mg: 64),
        .init(name: "Tea", mg: 47),
        .init(name: "Cola", mg: 34),
    ]
}

// MARK: - Editable draft (what the editor works on)

/// One night of the diary. `night` is the calendar day you went to bed
/// (the evening). Final wake is the following morning.
struct EntryDraft {
    var night: Date
    var tookMedication: Bool = true
    var medicationName: String = ""
    var medicationDose: String = ""
    var medicationTime: Date
    var bedTime: Date
    var sleepOnset: Date
    var awakenings: Int = 0
    var minutesAwake: Int = 0
    var finalWake: Date
    var caffeine: [CaffeineItem] = []
    var alcohol: [AlcoholItem] = []
    var naps: [NapItem] = []
    var rested: Int = 3
    var grogginess: Severity = .notPresent
    var daytimeSleepiness: Severity = .notPresent
    var dizziness: Severity = .notPresent
    var otherEffects: String = ""
    var notes: String = ""
    // Last night check-in. Kept in the app only, never written to Health.
    var healthSourceID: String = ""
    var fallAsleepFeel: FallAsleepFeel? = nil
    /// Start times of the Health wake-ups the user remembers.
    var rememberedWakes: [Date] = []
    var addedWakes: [AddedWake] = []
    var outOfBed: Date? = nil
    /// The dose was read from Health's Medications rather than entered in the app.
    var medicationFromHealth: Bool = false

    // Derived numbers, all in minutes.
    var latencyMinutes: Double { max(0, sleepOnset.timeIntervalSince(bedTime) / 60) }
    var timeInBedMinutes: Double { max(0, finalWake.timeIntervalSince(bedTime) / 60) }
    var totalSleepMinutes: Double {
        max(0, finalWake.timeIntervalSince(sleepOnset) / 60 - Double(minutesAwake))
    }
    var medToSleepMinutes: Double? {
        guard tookMedication else { return nil }
        return sleepOnset.timeIntervalSince(medicationTime) / 60
    }
    /// Caffeine this app logged (Health's own items excluded).
    var ownCaffeine: [CaffeineItem] { caffeine.filter { !$0.isFromHealth } }
    var totalCaffeineMg: Double { caffeine.reduce(0) { $0 + $1.mg } }
    var totalDrinks: Double { alcohol.reduce(0) { $0 + $1.drinks } }

    var problems: [String] {
        var p: [String] = []
        if sleepOnset < bedTime { p.append("Fell-asleep time is before bed time.") }
        if finalWake <= sleepOnset { p.append("Final wake is before you fell asleep.") }
        if Double(minutesAwake) > finalWake.timeIntervalSince(sleepOnset) / 60 {
            p.append("Minutes awake is longer than the whole night.")
        }
        return p
    }

    /// Re-place every time on the right calendar day after `night` changes.
    mutating func reanchor() {
        night = Calendar.current.startOfDay(for: night)
        medicationTime = TimeResolver.resolve(medicationTime, night: night, anchor: .evening)
        bedTime = TimeResolver.resolve(bedTime, night: night, anchor: .evening)
        sleepOnset = TimeResolver.resolve(sleepOnset, night: night, anchor: .evening)
        finalWake = TimeResolver.resolve(finalWake, night: night, anchor: .morning)
        for i in caffeine.indices {
            caffeine[i].time = TimeResolver.resolve(caffeine[i].time, night: night, anchor: .daytime)
        }
        for i in alcohol.indices {
            alcohol[i].time = TimeResolver.resolve(alcohol[i].time, night: night, anchor: .daytime)
        }
        for i in naps.indices {
            naps[i].start = TimeResolver.resolve(naps[i].start, night: night, anchor: .daytime)
        }
        for i in addedWakes.indices {
            addedWakes[i].start = TimeResolver.resolve(addedWakes[i].start, night: night, anchor: .evening)
        }
        if let o = outOfBed {
            outOfBed = TimeResolver.resolve(o, night: night, anchor: .morning)
        }
        // These belong to a specific Health recording of the old night.
        rememberedWakes = []
    }

    /// A fresh entry for the most likely night, carrying over the routine
    /// parts (medication, usual bed and wake times) from the previous entry.
    static func new(after previous: EntryDraft?, defaultMedicationName: String) -> EntryDraft {
        let night = TimeResolver.defaultNight()
        func at(_ h: Int, _ m: Int, _ a: TimeAnchor) -> Date {
            TimeResolver.at(hour: h, minute: m, night: night, anchor: a)
        }
        var d = EntryDraft(
            night: night,
            medicationName: defaultMedicationName,
            medicationTime: at(22, 30, .evening),
            bedTime: at(23, 0, .evening),
            sleepOnset: at(23, 20, .evening),
            finalWake: at(6, 30, .morning)
        )
        if let p = previous {
            d.tookMedication = p.tookMedication
            d.medicationName = p.medicationName.isEmpty ? defaultMedicationName : p.medicationName
            d.medicationDose = p.medicationDose
            d.medicationTime = p.medicationTime
            d.bedTime = p.bedTime
            d.sleepOnset = p.sleepOnset
            d.finalWake = p.finalWake
            d.reanchor()
        }
        return d
    }
}

// MARK: - Persisted model

@Model
final class DiaryEntry {
    var entryID: UUID = UUID()
    var night: Date = Date()
    var tookMedication: Bool = true
    var medicationName: String = ""
    var medicationDose: String = ""
    var medicationTime: Date = Date()
    var bedTime: Date = Date()
    var sleepOnset: Date = Date()
    var awakenings: Int = 0
    var minutesAwake: Int = 0
    var finalWake: Date = Date()
    var caffeineJSON: Data = Data()
    var alcoholJSON: Data = Data()
    var napsJSON: Data = Data()
    var rested: Int = 3
    var grogginess: Int = 0
    var daytimeSleepiness: Int = 0
    var dizziness: Int = 0
    var otherEffects: String = ""
    var notes: String = ""
    var healthSourceID: String = ""
    var fallAsleepFeel: String = ""
    var rememberedWakesJSON: Data = Data()
    var addedWakesJSON: Data = Data()
    var outOfBed: Date? = nil
    var lastNightConfirmedAt: Date? = nil
    var medicationConfirmedAt: Date? = nil
    var yesterdayConfirmedAt: Date? = nil
    var morningConfirmedAt: Date? = nil
    var medicationFromHealth: Bool = false
    var updatedAt: Date = Date()
    var healthSyncedAt: Date? = nil
    var healthSyncError: String? = nil

    init(draft: EntryDraft) {
        self.entryID = UUID()
        apply(draft)
    }

    func apply(_ d: EntryDraft) {
        night = Calendar.current.startOfDay(for: d.night)
        tookMedication = d.tookMedication
        medicationName = d.medicationName
        medicationDose = d.medicationDose
        medicationTime = d.medicationTime
        bedTime = d.bedTime
        sleepOnset = d.sleepOnset
        awakenings = d.awakenings
        minutesAwake = d.minutesAwake
        finalWake = d.finalWake
        caffeineJSON = encodeList(d.caffeine)
        alcoholJSON = encodeList(d.alcohol)
        napsJSON = encodeList(d.naps)
        rested = d.rested
        grogginess = d.grogginess.rawValue
        daytimeSleepiness = d.daytimeSleepiness.rawValue
        dizziness = d.dizziness.rawValue
        otherEffects = d.otherEffects
        notes = d.notes
        healthSourceID = d.healthSourceID
        fallAsleepFeel = d.fallAsleepFeel?.rawValue ?? ""
        rememberedWakesJSON = encodeList(d.rememberedWakes)
        addedWakesJSON = encodeList(d.addedWakes)
        outOfBed = d.outOfBed
        medicationFromHealth = d.medicationFromHealth
        updatedAt = Date()
    }

    var draft: EntryDraft {
        EntryDraft(
            night: night,
            tookMedication: tookMedication,
            medicationName: medicationName,
            medicationDose: medicationDose,
            medicationTime: medicationTime,
            bedTime: bedTime,
            sleepOnset: sleepOnset,
            awakenings: awakenings,
            minutesAwake: minutesAwake,
            finalWake: finalWake,
            caffeine: decodeList(caffeineJSON),
            alcohol: decodeList(alcoholJSON),
            naps: decodeList(napsJSON),
            rested: rested,
            grogginess: Severity(rawValue: grogginess) ?? .notPresent,
            daytimeSleepiness: Severity(rawValue: daytimeSleepiness) ?? .notPresent,
            dizziness: Severity(rawValue: dizziness) ?? .notPresent,
            otherEffects: otherEffects,
            notes: notes,
            healthSourceID: healthSourceID,
            fallAsleepFeel: FallAsleepFeel(rawValue: fallAsleepFeel),
            rememberedWakes: decodeList(rememberedWakesJSON),
            addedWakes: decodeList(addedWakesJSON),
            outOfBed: outOfBed,
            medicationFromHealth: medicationFromHealth
        )
    }
}

private func encodeList<T: Encodable>(_ list: [T]) -> Data {
    (try? JSONEncoder().encode(list)) ?? Data()
}

private func decodeList<T: Decodable>(_ data: Data) -> [T] {
    guard !data.isEmpty else { return [] }
    return (try? JSONDecoder().decode([T].self, from: data)) ?? []
}
