import Foundation

/// What to tell the user after asking for Health access.
enum HealthAccessText {
    static let settingsPath = "Settings › Privacy & Security › Health › Sleep Diary"

    static func message(for result: HealthAccessResult) -> String {
        switch result {
        case .asked:
            return "Done. If something is still missing, check the switches in \(settingsPath)."
        case .alreadyAnswered:
            return "iOS only shows the permission sheet once. To change what Sleep Diary can read or write, go to \(settingsPath)."
        case .unavailable:
            return "Apple Health isn't available on this device."
        case .failed(let message):
            return "Couldn't ask for Health access: \(message)"
        }
    }
}
