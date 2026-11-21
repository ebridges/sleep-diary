import SwiftUI
import SwiftData

/// After the last step: a recap of the night, what went to Health and what stayed in the app.
struct SavedView: View {
    let checkIn: CheckIn
    let onDone: () -> Void

    @Query(sort: \DiaryEntry.night, order: .reverse) private var entries: [DiaryEntry]
    @State private var reminderAt: Date?
    @State private var reminderRefused = false

    private var d: EntryDraft { checkIn.d }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 64, height: 64)
                        .background(Theme.success, in: Circle())
                    Text("\(Fmt.weekday(checkIn.night)) night saved")
                        .font(.system(size: 26, weight: .semibold))
                    Text(progressText)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                Card(spacing: 4) {
                    CardLabel(text: "Your diary")
                    row(d.medicationName.isEmpty ? "Medication" : d.medicationName, medicationText)
                    row("In bed / asleep", "\(Fmt.time(d.bedTime)) / \(Fmt.time(d.sleepOnset))")
                    row("Wake-ups", wakeText)
                    row("Woke for good", Fmt.time(d.finalWake))
                    row("Caffeine · alcohol · nap", intakeText)
                    row("Rested · groggy", "\(d.rested) of 5 · \(d.grogginess.label)")
                }

                Card(spacing: 4) {
                    Label {
                        CardLabel(text: "Written to Apple Health")
                    } icon: {
                        Image(systemName: "heart").foregroundStyle(Theme.accent)
                    }
                    if let error = checkIn.healthError {
                        Text("Couldn't save to Health: \(error)")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.accent)
                    } else if checkIn.healthLines.isEmpty {
                        row("This night", "Nothing to write")
                    } else {
                        ForEach(checkIn.healthLines) { row($0.label, $0.value) }
                    }
                    Text("Your rested score, remembered wake-ups, your own times and any dose you added stay in Sleep Diary. Health has no place for them.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 6)
                }

                Button("Done", action: onDone)
                    .buttonStyle(WideButtonStyle())
                reminderLink
            }
            .padding(20)
        }
        .nightStyle()
        .navigationBarBackButtonHidden(true)
        .task { reminderAt = await Reminder.pendingAfternoon() }
    }

    @ViewBuilder
    private var reminderLink: some View {
        if let reminderAt {
            Label("Reminder set for \(Fmt.time(reminderAt))", systemImage: "bell")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
                .frame(minHeight: 44)
        } else if reminderRefused {
            Text("Notifications are off for Sleep Diary. Turn them on in Settings › Notifications.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        } else {
            Button("Remind me to log how I feel this afternoon") {
                Task {
                    reminderAt = await Reminder.scheduleAfternoon()
                    reminderRefused = reminderAt == nil
                }
            }
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 30)
    }

    private var progressText: String {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: Date())) ?? .distantPast
        let n = min(14, entries.filter { $0.night >= cutoff && $0.lastNightConfirmedAt != nil }.count)
        return n >= 14
            ? "Thanks. You have two weeks of nights for the report."
            : "Thanks. That's \(n) of 14 nights toward a two-week report."
    }

    private var medicationText: String {
        guard d.tookMedication else { return "Not taken" }
        let amount = d.medicationDose.isEmpty ? "" : "\(d.medicationDose) "
        return "\(amount)at \(Fmt.time(d.medicationTime))"
    }

    private var wakeText: String {
        let recorded = checkIn.current?.wakes.count
        var parts = ["\(d.rememberedWakes.count) remembered"]
        if let recorded { parts.append("\(recorded) recorded") }
        if !d.addedWakes.isEmpty { parts.append("\(d.addedWakes.count) added") }
        return parts.joined(separator: ", ")
    }

    private var intakeText: String {
        let caffeine = d.caffeine.isEmpty ? "None" : "\(Int(d.totalCaffeineMg)) mg"
        let alcohol = d.alcohol.isEmpty ? "none" : "\(Fmt.number(d.totalDrinks)) drink\(d.totalDrinks == 1 ? "" : "s")"
        let nap = d.naps.isEmpty ? "none" : Fmt.hm(Double(d.naps.reduce(0) { $0 + $1.minutes }))
        return "\(caffeine) · \(alcohol) · \(nap)"
    }
}
