import SwiftUI

/// Check-in step 1: confirm the evening dose Health's Medications recorded.
///
/// HealthKit lets apps read dose events but not create them, so a dose added
/// here is kept in the diary only.
struct MedicationView: View {
    @Bindable var checkIn: CheckIn
    let onDone: () -> Void

    @AppStorage(SettingsKeys.defaultMedicationName) private var medicationName = ""
    @AppStorage(SettingsKeys.writeSleepToHealth) private var writeNaps = false

    private enum Choice { case confirmHealth, editHealth, addManually, didNotTake }
    @State private var choice: Choice?
    @State private var time = Date()
    @State private var amount = ""
    @State private var saving = false

    var body: some View {
        StepScaffold(step: .medication, title: "Medication", subtitle: "\(Fmt.weekday(checkIn.night)) evening") {
            switch checkIn.medication {
            case nil:
                Card { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
            case .found(let dose)?:
                foundCard(dose)
                foundActions(dose)
            case let lookup?:
                missingCard(lookup)
            }
        }
        .task {
            if checkIn.medication == nil { await checkIn.loadMedication(name: medicationName) }
        }
        .onChange(of: checkIn.medication) { setUp() }
        .onAppear { setUp() }
    }

    // MARK: Found in Health

    private func foundCard(_ dose: MedicationDose) -> some View {
        Card(spacing: 14) {
            Label("From Apple Health · Medications", systemImage: "heart")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 14) {
                Image(systemName: "pills")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.rem)
                    .frame(width: 52, height: 52)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(dose.name).font(.system(size: 24, weight: .semibold))
                    Text("\(choice == .editHealth ? amount : dose.amount) · logged as taken")
                        .foregroundStyle(Theme.secondary)
                }
            }
            Divider().overlay(Theme.line)
            if choice == .editHealth {
                editors
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Taken at").font(.system(size: 15, weight: .medium))
                        Text(Fmt.shortDay(dose.time)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Text(Fmt.time(dose.time))
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if let line = doseToSleepText(choice == .editHealth ? time : dose.time) {
                Text(line).font(.system(size: 14)).foregroundStyle(Theme.secondary)
            }
        }
    }

    @ViewBuilder
    private func foundActions(_ dose: MedicationDose) -> some View {
        if choice == .editHealth {
            Button("Save changes") { save(took: true, fromHealth: false) }
                .buttonStyle(WideButtonStyle())
            Button("Cancel changes") { choice = .confirmHealth; time = dose.time; amount = dose.amount }
                .buttonStyle(WideButtonStyle(primary: false))
        } else {
            Text("Is this right?").font(Theme.cardTitleFont)
            Button("Yes, that's right") {
                time = dose.time
                amount = dose.amount
                save(took: true, fromHealth: true)
            }
            .buttonStyle(WideButtonStyle())
            Button("Change the time or dose") { choice = .editHealth }
                .buttonStyle(WideButtonStyle(primary: false))
            Button("I didn't take it last night") { save(took: false, fromHealth: false) }
                .buttonStyle(WideButtonStyle(primary: false))
        }
    }

    // MARK: Not in Health

    private func missingCard(_ lookup: MedicationLookup) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Text("No \(medicationName.lowercased()) found for \(Fmt.weekday(checkIn.night)) night")
                    .font(.system(size: 15, weight: .semibold))
                Text(missingExplanation(lookup))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                FlowRow {
                    Chip(title: "Add usual dose", selected: choice == .addManually) { choice = .addManually }
                    Chip(title: "Didn't take it", selected: choice == .didNotTake) { choice = .didNotTake }
                }
                if choice == .addManually {
                    editors
                    Text("Kept in Sleep Diary. Apps can read doses from Health's Medications but can't add them.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }
            if lookup == .notShared {
                Button("Choose medications to share") {
                    Task { await checkIn.requestMedicationAccess(name: medicationName) }
                }
                .buttonStyle(WideButtonStyle(primary: false))
            }
            Button("Next") {
                save(took: choice == .addManually, fromHealth: false)
            }
            .buttonStyle(WideButtonStyle())
            .disabled(choice == nil || saving)
            .opacity(choice == nil ? 0.5 : 1)
        }
    }

    private func missingExplanation(_ lookup: MedicationLookup) -> String {
        let usual = checkIn.d.medicationDose.isEmpty
            ? "Your usual time is around \(Fmt.time(checkIn.d.medicationTime))."
            : "Your usual is \(checkIn.d.medicationDose) around \(Fmt.time(checkIn.d.medicationTime))."
        switch lookup {
        case .unsupported:
            return "Reading Health's Medications needs iOS 26. \(usual)"
        case .notShared:
            return "Health isn't sharing a medication named \(medicationName) with Sleep Diary. \(usual)"
        default:
            return "Nothing was logged as taken that evening. \(usual)"
        }
    }

    // MARK: Shared

    private var editors: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Taken at").font(.system(size: 15, weight: .medium))
                Spacer()
                DatePicker("Taken at", selection: Binding(
                    get: { time },
                    set: { time = TimeResolver.resolve($0, night: checkIn.night, anchor: .evening) }
                ), displayedComponents: .hourAndMinute)
                .labelsHidden()
            }
            .frame(minHeight: 44)
            HStack {
                Text("Dose").font(.system(size: 15, weight: .medium))
                Spacer()
                TextField("e.g. 1 tablet", text: $amount)
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

    private func setUp() {
        guard choice == nil, let lookup = checkIn.medication else { return }
        switch lookup {
        case .found(let dose):
            time = dose.time
            amount = dose.amount
            choice = .confirmHealth
        default:
            time = checkIn.d.medicationTime
            amount = checkIn.d.medicationDose
            if checkIn.isDone(.medication) {
                choice = checkIn.d.tookMedication ? .addManually : .didNotTake
            }
        }
    }

    private func save(took: Bool, fromHealth: Bool) {
        checkIn.d.tookMedication = took
        if took {
            if case .found(let dose)? = checkIn.medication { checkIn.d.medicationName = dose.name }
            if checkIn.d.medicationName.isEmpty { checkIn.d.medicationName = medicationName }
            checkIn.d.medicationTime = time
            checkIn.d.medicationDose = amount
        }
        checkIn.d.medicationFromHealth = took && fromHealth
        saving = true
        Task {
            await checkIn.confirm(.medication, writeNaps: writeNaps)
            saving = false
            onDone()
        }
    }
}
