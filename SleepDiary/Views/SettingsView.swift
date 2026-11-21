import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthManager.self) private var health

    @AppStorage(MedicationSettings.key) private var rawMedications = ""
    @State private var accessMessage: String?
    /// Medications Health shares with the app, and apps that have recorded sleep.
    @State private var medicationNames: [String] = []
    @State private var sleepSources: [String] = []
    @State private var loaded = false
    /// Usual dose and time read from Health, per chosen medication.
    @State private var routines: [String: MedicationRoutine] = [:]

    private var chosenMedications: [String] { MedicationSettings.names(rawMedications) }
    @AppStorage(SettingsKeys.defaultCaffeineMg) private var defaultCaffeineMg = 95.0
    @AppStorage(SettingsKeys.writeSleepToHealth) private var writeSleep = false
    @AppStorage(SettingsKeys.preferredSource) private var preferredSource = ""
    @AppStorage(SettingsKeys.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKeys.reminderMinutes) private var reminderMinutes = 7 * 60 + 30

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sleep source", selection: $preferredSource) {
                        Text("Most sleep recorded").tag("")
                        ForEach(choices(sleepSources, keeping: preferredSource), id: \.self) { Text($0).tag($0) }
                    }

                    Text("Medications")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(chosenMedications, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                            Text(routineText(name))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        var list = chosenMedications
                        list.remove(atOffsets: offsets)
                        rawMedications = MedicationSettings.raw(list)
                    }
                    let addable = medicationNames.filter { !chosenMedications.contains($0) }
                    if !addable.isEmpty {
                        Menu {
                            ForEach(addable, id: \.self) { name in
                                Button(name) { rawMedications = MedicationSettings.raw(chosenMedications + [name]) }
                            }
                        } label: {
                            Label("Add medication", systemImage: "plus")
                        }
                    } else if loaded {
                        Text(medicationNames.isEmpty
                             ? "No medications are shared with Sleep Diary yet."
                             : "All shared medications are added.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose medications to share") {
                        Task {
                            await health.requestMedicationAccess()
                            medicationNames = await health.sharedMedicationNames()
                        }
                    }

                    Toggle("Write naps to Health", isOn: $writeSleep)
                    Button("Ask for Health access again") {
                        Task { accessMessage = HealthAccessText.message(for: await health.requestAuthorization()) }
                    }
                    if let accessMessage {
                        Text(accessMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Sleep source is used when more than one app or device recorded the same night. Medications come from those you've added in the Health app and shared with Sleep Diary; swipe left to remove one. Caffeine, alcohol, grogginess, symptoms and (if on) naps are saved to Health; your corrections to the night stay in the app. Permissions: \(HealthAccessText.settingsPath).")
                }

                Section {
                    Stepper(value: $defaultCaffeineMg, in: 10...500, step: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\"Other\" caffeine: \(Int(defaultCaffeineMg)) mg")
                            Text(CaffeineGuide.describe(defaultCaffeineMg))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Defaults for new nights")
                } footer: {
                    Text("The starting amount for \"Other\" in the caffeine list. For reference: drip coffee has about 40 mg per 100 ml (a 300 ml cup is about 120 mg), an espresso shot about 64 mg, 240 ml of black tea about 47 mg, and a can of cola about 34 mg.")
                }

                Section("Morning reminder") {
                    Toggle("Remind me to fill in the diary", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                medicationNames = await health.sharedMedicationNames()
                sleepSources = await health.sleepSourceNames()
                loaded = true
            }
            .task(id: rawMedications) { await loadRoutines() }
            .onChange(of: reminderEnabled) { updateReminder() }
            .onChange(of: reminderMinutes) { updateReminder() }
        }
    }

    /// Reads each chosen medication's usual dose and time from Health.
    private func loadRoutines() async {
        var found: [String: MedicationRoutine] = [:]
        for name in chosenMedications {
            found[name] = await health.medicationRoutine(matching: name)
        }
        guard !Task.isCancelled else { return }
        routines = found
    }

    private func routineText(_ name: String) -> String {
        guard let r = routines[name] else { return "No recent doses in Apple Health" }
        return "\(r.amount) at \(Fmt.minutes(r.minutes)), \(r.scheduled ? "scheduled in Apple Health" : "last logged in Apple Health")"
    }

    /// The options for a picker, plus the saved value if Health no longer lists it,
    /// so it stays visible and selected.
    private func choices(_ options: [String], keeping current: String) -> [String] {
        current.isEmpty || options.contains(current) ? options : [current] + options
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                reminderMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    private func updateReminder() {
        let enabled = reminderEnabled
        let minutes = reminderMinutes
        Task { await Reminder.update(enabled: enabled, minutesAfterMidnight: minutes) }
    }
}
