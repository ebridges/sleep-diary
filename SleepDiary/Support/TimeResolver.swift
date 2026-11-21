import Foundation

/// Which side of midnight a clock time belongs to, relative to the night.
enum TimeAnchor {
    /// Medication, bed, falling asleep: noon or later is the evening of `night`,
    /// earlier is after midnight (the next calendar day).
    case evening
    /// Final wake: the morning after `night` (unless it's 6 pm or later).
    case morning
    /// Caffeine, alcohol, naps: the day of `night`; times before 4 am count as
    /// after midnight.
    case daytime
}

enum TimeResolver {
    static var calendar: Calendar { .current }

    static func resolve(_ time: Date, night: Date, anchor: TimeAnchor) -> Date {
        let c = calendar.dateComponents([.hour, .minute], from: time)
        return at(hour: c.hour ?? 0, minute: c.minute ?? 0, night: night, anchor: anchor)
    }

    static func at(hour: Int, minute: Int, night: Date, anchor: TimeAnchor) -> Date {
        let base = calendar.startOfDay(for: night)
        let offset: Int
        switch anchor {
        case .evening: offset = hour >= 12 ? 0 : 1
        case .morning: offset = hour >= 18 ? 0 : 1
        case .daytime: offset = hour >= 4 ? 0 : 1
        }
        let day = calendar.date(byAdding: .day, value: offset, to: base) ?? base
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// Before 3 pm you're probably logging last night; after that, tonight.
    static func defaultNight(now: Date = Date()) -> Date {
        let today = calendar.startOfDay(for: now)
        if calendar.component(.hour, from: now) < 15 {
            return calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        return today
    }
}

enum Fmt {
    static func time(_ d: Date?) -> String {
        guard let d else { return "–" }
        return d.formatted(date: .omitted, time: .shortened)
    }

    static func hm(_ minutes: Double?) -> String {
        guard let minutes else { return "–" }
        let m = Int(minutes.rounded())
        if m < 0 { return "-" + hm(Double(-m)) }
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    static func night(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Fri Nov 20"
    static func shortDay(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .replacingOccurrences(of: ",", with: "")
    }

    /// "Thursday"
    static func weekday(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.wide))
    }

    /// "Friday, Nov 20"
    static func longDay(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func number(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
    }
}

enum SettingsKeys {
    static let defaultMedicationName = "defaultMedicationName"
    static let defaultCaffeineMg = "defaultCaffeineMg"
    static let writeSleepToHealth = "writeSleepToHealth"
    static let preferredSource = "preferredSource"
    static let reminderEnabled = "reminderEnabled"
    static let reminderMinutes = "reminderMinutes"
}
