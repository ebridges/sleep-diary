import Foundation
import SwiftData
import HealthKit

/// What the user can log during the day.
enum SymptomKind: String, CaseIterable, Identifiable, Codable {
    case sleepiness, dizziness, grogginess, headache, dryMouth, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleepiness: return "Sleepiness"
        case .dizziness: return "Dizziness"
        case .grogginess: return "Grogginess"
        case .headache: return "Headache"
        case .dryMouth: return "Dry mouth"
        case .other: return "Other"
        }
    }

    /// The Health symptom it's written as. Sleepiness and grogginess are both
    /// Fatigue. HealthKit has no Dry Mouth type, so dry mouth and "Other" stay in the app.
    var healthType: HKCategoryType? {
        switch self {
        case .sleepiness, .grogginess: return HKCategoryType(.fatigue)
        case .dizziness: return HKCategoryType(.dizziness)
        case .headache: return HKCategoryType(.headache)
        case .dryMouth, .other: return nil
        }
    }

    var healthName: String? {
        switch self {
        case .sleepiness, .grogginess: return "Fatigue"
        case .dizziness: return "Dizziness"
        case .headache: return "Headache"
        case .dryMouth, .other: return nil
        }
    }
}

/// One symptom logged during the day, with its own time.
@Model
final class SymptomEntry {
    var entryID: UUID = UUID()
    var time: Date = Date()
    var kindRaw: String = SymptomKind.other.rawValue
    /// What the user typed for "Other".
    var otherName: String = ""
    var severityRaw: Int = 0
    var healthSyncedAt: Date? = nil
    var healthSyncError: String? = nil

    init(time: Date, kind: SymptomKind, otherName: String = "", severity: Severity) {
        self.entryID = UUID()
        self.time = time
        self.kindRaw = kind.rawValue
        self.otherName = otherName
        self.severityRaw = severity.rawValue
    }

    var kind: SymptomKind { SymptomKind(rawValue: kindRaw) ?? .other }
    var severity: Severity { Severity(rawValue: severityRaw) ?? .notPresent }

    var name: String {
        kind == .other && !otherName.isEmpty ? otherName : kind.label
    }
}
