import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthManager.self) private var health

    @AppStorage(SettingsKeys.defaultMedicationName) private var defaultMedicationName = ""
    @AppStorage(SettingsKeys.defaultMedicationDose) private var defaultMedicationDose = ""
    @AppStorage(SettingsKeys.defaultMedicationMinutes) private var defaultMedicationMinutes = 22 * 60 + 30
    @State private var accessMessage: String?
    @AppStorage(SettingsKeys.defaultCaffeineMg) private var defaultCaffeineMg = 95.0
    @AppStorage(SettingsKeys.writeSleepToHealth) private var writeSleep = false
    @AppStorage(SettingsKeys.preferredSource) private var preferredSource = ""
    @AppStorage(SettingsKeys.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKeys.reminderMinutes) private var reminderMinutes = 7 * 60 + 30

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name as shown in the Health app", text: $defaultMedicationName)
                        .autocorrectionDisabled()
                    TextField("Usual dose, e.g. 1 tablet", text: $defaultMedicationDose)
                    DatePicker("Usual time", selection: minutesBinding($defaultMedicationMinutes),
                               displayedComponents: .hourAndMinute)
                } header: {
                    Text("Evening medication")
                } footer: {
                    Text("The check-in looks for this medication's evening dose in Apple Health's Medications. Use the name or nickname shown in the Health app. The usual dose and time fill in \"Add usual dose\" when Health has nothing logged. Leave the name empty if you don't take one.")
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
                        Task { accessMessage = HealthAccessText.message(for: await health.requestAuthorization()) }
                    }
                    if let accessMessage {
                        Text(accessMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Caffeine, alcohol, grogginess, symptoms and (if switched on) naps are saved to Health. Your corrections to the night are kept in the app and never written to Health, so Apple Watch or AutoSleep stays the record. To change permissions: \(HealthAccessText.settingsPath).")
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

    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
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
