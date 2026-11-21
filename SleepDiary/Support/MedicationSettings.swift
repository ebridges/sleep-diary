import Foundation

/// The medications chosen in Settings, stored as one name per line under `key`.
enum MedicationSettings {
    static let key = "medicationNames"

    static func names(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func raw(_ names: [String]) -> String {
        names.joined(separator: "\n")
    }

    /// Earlier versions kept a single medication name; carry it over once.
    static func migrate(_ defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: key) == nil,
              let old = defaults.string(forKey: SettingsKeys.defaultMedicationName), !old.isEmpty else { return }
        defaults.set(old, forKey: key)
    }
}
