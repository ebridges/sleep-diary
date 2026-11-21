import SwiftUI

/// Check-in step 4: for each medication chosen in Settings, did you take it last night?
///
/// Each card shows what Health's Medications recorded that evening and the
/// medication's schedule. Time and dose are prefilled from the recorded dose,
/// else the usual dose and time (Health's recent doses, then the last night in
/// the diary). HealthKit lets apps read dose events but not create them, so what's
/// confirmed here stays in the diary.
struct MedicationView: View {
    @Bindable var checkIn: CheckIn
    let onDone: () -> Void

    @AppStorage(MedicationSettings.key) private var rawMedications = ""
    @AppStorage(SettingsKeys.writeSleepToHealth) private var writeNaps = false

    private struct Answer {
        /// nil until answered.
        var took: Bool?
        var time: Date
        var dose: String
    }

    @State private var answers: [String: Answer] = [:]
    @State private var saving = false
    @State private var showingSettings = false

    private var names: [String] { MedicationSettings.names(rawMedications) }

    private var allAnswered: Bool {
        names.allSatisfy { answers[$0]?.took != nil }
    }

    var body: some View {
        StepScaffold(step: .medication, title: "Medication", subtitle: "\(Fmt.weekday(checkIn.night)) evening") {
            if names.isEmpty {
                notSetCard
            } else {
                ForEach(names, id: \.self) { name in medicationCard(name) }
                Button("Next", action: save)
                    .buttonStyle(WideButtonStyle())
                    .disabled(!allAnswered || saving)
                    .opacity(allAnswered ? 1 : 0.5)
            }
        }
        // Re-runs (cancelling the previous lookup) whenever the list in Settings changes.
        .task(id: rawMedications) {
            let names = names
            if checkIn.medicationsLookedUp != names {
                await checkIn.loadMedications(names)
                guard !Task.isCancelled else { return }
            }
            for name in names where answers[name] == nil {
                answers[name] = prefill(name)
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    // MARK: Cards

    private func medicationCard(_ name: String) -> some View {
        let took = answers[name]?.took
        return Card {
            Text(name).font(Theme.cardTitleFont)
            FlowRow {
                Chip(title: "Took it", selected: took == true) { answers[name]?.took = true }
                Chip(title: "Didn't take it", selected: took == false) { answers[name]?.took = false }
            }
            healthBlock(name)
            if took == true {
                Divider().overlay(Theme.line)
                editors(name)
                if let time = answers[name]?.time, let line = doseToSleepText(time) {
                    Text(line).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private var notSetCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Text("No medications added").font(.system(size: 15, weight: .semibold))
                Text("Add the medications you take in the evening in Settings › Apple Health. If you don't take any, skip this step.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
            }
            Button("Open Settings") { showingSettings = true }
                .buttonStyle(WideButtonStyle(primary: false))
            Button("Skip", action: save)
                .buttonStyle(WideButtonStyle())
                .disabled(saving)
        }
    }

    /// What Apple Health recorded for that evening, and the medication's schedule.
    @ViewBuilder
    private func healthBlock(_ name: String) -> some View {
        if let recorded = recordedLine(name) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Apple Health", systemImage: "heart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                healthRow("Recorded", recorded)
                if let routine = checkIn.medicationRoutines[name] {
                    healthRow(routine.scheduled ? "Scheduled" : "Usually",
                              "\(routine.amount) at \(Fmt.minutes(routine.minutes))")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func healthRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 14))
    }

    /// What Health's Medications logged for this medication that evening.
    private func recordedLine(_ name: String) -> String? {
        guard checkIn.medicationsLookedUp != nil else { return "Checking…" }
        switch checkIn.medicationLookups[name] {
        case .found(let dose)?:
            return "\(dose.amount) taken at \(Fmt.time(dose.time))"
        case .noDose?:
            return "Nothing logged that evening"
        case .notShared?, .noMatch?:
            return "Not shared with Sleep Diary (Settings › Apple Health)"
        case .failed(let message)?:
            return "Couldn't read: \(message)"
        case .unsupported?, .notSet?, nil:
            return nil
        }
    }

    private func editors(_ name: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Taken at").font(.system(size: 15, weight: .medium))
                Spacer()
                DatePicker("Taken at", selection: Binding(
                    get: { answers[name]?.time ?? Date() },
                    set: { answers[name]?.time = TimeResolver.resolve($0, night: checkIn.night, anchor: .evening) }
                ), displayedComponents: .hourAndMinute)
                .labelsHidden()
            }
            .frame(minHeight: 44)
            HStack {
                Text("Dose").font(.system(size: 15, weight: .medium))
                Spacer()
                TextField("e.g. 1 tablet", text: Binding(
                    get: { answers[name]?.dose ?? "" },
                    set: { answers[name]?.dose = $0 }
                ))
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 12)
                .frame(maxWidth: 180, minHeight: 40)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
            }
            .frame(minHeight: 44)
        }
    }

    private func doseToSleepText(_ doseTime: Date) -> String? {
        guard let onset = checkIn.current?.sleepOnset else { return nil }
        let minutes = Int((onset.timeIntervalSince(doseTime) / 60).rounded())
        if minutes >= 0 {
            return "Health shows you asleep at \(Fmt.time(onset)), \(Fmt.hm(Double(minutes))) after this dose."
        }
        return "Health shows you asleep at \(Fmt.time(onset)), \(Fmt.hm(Double(-minutes))) before this dose."
    }

    // MARK: Prefill and save

    private func healthDose(_ name: String) -> MedicationDose? {
        if case .found(let dose)? = checkIn.medicationLookups[name] { return dose }
        return nil
    }

    /// The starting answer for one medication: what was saved for this night,
    /// else the dose Health logged, else the usual dose and time.
    private func prefill(_ name: String) -> Answer {
        if checkIn.isDone(.medication), let saved = checkIn.d.medications.first(where: { $0.name == name }) {
            return Answer(took: saved.took, time: saved.time, dose: saved.dose)
        }
        if let dose = healthDose(name) {
            return Answer(took: true, time: dose.time, dose: dose.amount)
        }
        let previous = checkIn.previousMedications.first { $0.name == name && $0.took }
        let routine = checkIn.medicationRoutines[name]
        let time: Date
        if let routine {
            time = TimeResolver.at(hour: routine.minutes / 60, minute: routine.minutes % 60,
                                   night: checkIn.night, anchor: .evening)
        } else if let previous {
            time = TimeResolver.resolve(previous.time, night: checkIn.night, anchor: .evening)
        } else {
            time = TimeResolver.at(hour: 22, minute: 0, night: checkIn.night, anchor: .evening)
        }
        return Answer(took: nil, time: time, dose: routine?.amount ?? previous?.dose ?? "")
    }

    private func save() {
        let records = names.compactMap { name -> MedicationRecord? in
            guard let a = answers[name] else { return nil }
            let took = a.took == true
            let fromHealth = took && healthDose(name).map { abs($0.time.timeIntervalSince(a.time)) < 60 } == true
            return MedicationRecord(name: name, took: took, time: a.time, dose: a.dose, fromHealth: fromHealth)
        }
        checkIn.d.medications = records

        // The single medication fields summarize what was taken.
        let taken = records.filter(\.took)
        checkIn.d.tookMedication = !taken.isEmpty
        if !taken.isEmpty {
            checkIn.d.medicationName = taken.map(\.name).joined(separator: ", ")
            checkIn.d.medicationDose = taken.map(\.dose).filter { !$0.isEmpty }.joined(separator: ", ")
            checkIn.d.medicationTime = taken.map(\.time).min() ?? checkIn.d.medicationTime
        }
        checkIn.d.medicationFromHealth = !taken.isEmpty && taken.allSatisfy(\.fromHealth)

        saving = true
        Task {
            await checkIn.confirm(.medication, writeNaps: writeNaps)
            saving = false
            onDone()
        }
    }
}
