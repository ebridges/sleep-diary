import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthManager.self) private var health

    @AppStorage(SettingsKeys.defaultMedicationName) private var defaultMedicationName = ""
    @AppStorage(SettingsKeys.defaultCaffeineMg) private var defaultCaffeineMg = 95.0
    @AppStorage(SettingsKeys.writeSleepToHealth) private var writeSleep = false
    @AppStorage(SettingsKeys.preferredSource) private var preferredSource = ""
    @AppStorage(SettingsKeys.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKeys.reminderMinutes) private var reminderMinutes = 7 * 60 + 30

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults for new nights") {
                    TextField("Medication name", text: $defaultMedicationName)
                    Stepper("\"Other\" caffeine: \(Int(defaultCaffeineMg)) mg",
                            value: $defaultCaffeineMg, in: 0...500, step: 5)
                }

                Section {
                    TextField("e.g. AutoSleep or Apple Watch", text: $preferredSource)
                        .autocorrectionDisabled()
                } header: {
                    Text("Preferred sleep source")
                } footer: {
                    Text("Used when more than one app recorded the same night. Leave blank to use whichever recorded the most sleep.")
                }

                Section {
                    Toggle("Write naps to Health", isOn: $writeSleep)
                    Button("Ask for Health access again") {
                        Task { await health.requestAuthorization() }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Caffeine, alcohol, grogginess or daytime sleepiness (as Fatigue) and dizziness are always saved to Health. Naps are off by default. Your corrections to the night are kept in the app and never written to Health, so Apple Watch or AutoSleep stays the record. To change permissions: Settings › Health › Data Access & Devices › Sleep Diary.")
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
            .onChange(of: reminderEnabled) { updateReminder() }
            .onChange(of: reminderMinutes) { updateReminder() }
        }
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
