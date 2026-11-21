import SwiftUI
import SwiftData

struct EntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(HealthManager.self) private var health
    @AppStorage(SettingsKeys.writeSleepToHealth) private var writeSleep = false
    @AppStorage(SettingsKeys.defaultCaffeineMg) private var defaultCaffeineMg = 95.0

    let entry: DiaryEntry?
    @State private var d: EntryDraft

    init(entry: DiaryEntry?, newDraft: EntryDraft? = nil) {
        self.entry = entry
        let initial = entry?.draft
            ?? newDraft
            ?? EntryDraft.new(after: nil, defaultMedicationName: "")
        _d = State(initialValue: initial)
    }

    var body: some View {
        Form {
            nightSection
            medicationSection
            sleepSection
            caffeineSection
            alcoholSection
            napSection
            morningSection
            daySection
            Section("Notes") {
                TextField("Anything else worth noting", text: $d.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
            HealthComparisonView(draft: d)
        }
        .navigationTitle(entry == nil ? "New night" : Fmt.night(d.night))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.bold()
            }
        }
    }

    // MARK: Sections

    private var nightSection: some View {
        Section {
            DatePicker("Night of", selection: nightBinding, in: ...Date(), displayedComponents: .date)
        } footer: {
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: d.night) ?? d.night
            Text("Bed on the evening of \(Fmt.night(d.night)), up on the morning of \(Fmt.night(nextDay)).")
        }
    }

    private var medicationSection: some View {
        Section("Medication") {
            Toggle("Took medication", isOn: $d.tookMedication)
            if d.tookMedication {
                TextField("Name", text: $d.medicationName)
                TextField("Dose, e.g. 50 mg", text: $d.medicationDose)
                DatePicker("Time taken", selection: anchored($d.medicationTime, .evening),
                           displayedComponents: .hourAndMinute)
            }
        }
    }

    private var sleepSection: some View {
        Section {
            DatePicker("Got into bed", selection: anchored($d.bedTime, .evening),
                       displayedComponents: .hourAndMinute)
            DatePicker("Think I fell asleep", selection: anchored($d.sleepOnset, .evening),
                       displayedComponents: .hourAndMinute)
            Stepper("Woke up \(d.awakenings) time\(d.awakenings == 1 ? "" : "s")",
                    value: $d.awakenings, in: 0...30)
            if d.awakenings > 0 {
                Stepper("Awake about \(Fmt.hm(Double(d.minutesAwake))) in total",
                        value: $d.minutesAwake, in: 0...600, step: 5)
            }
            DatePicker("Final wake", selection: anchored($d.finalWake, .morning),
                       displayedComponents: .hourAndMinute)
        } header: {
            Text("The night")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("About \(Fmt.hm(d.totalSleepMinutes)) asleep. Took \(Fmt.hm(d.latencyMinutes)) to fall asleep.")
                ForEach(d.problems, id: \.self) { Text($0).foregroundStyle(.red) }
            }
        }
    }

    private var caffeineSection: some View {
        Section {
            ForEach($d.caffeine) { $item in
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Drink", text: $item.label)
                        DatePicker("Time", selection: anchored($item.time, .daytime),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Stepper("\(Int(item.mg)) mg", value: $item.mg, in: 0...1000, step: 5)
                }
            }
            .onDelete { d.caffeine.remove(atOffsets: $0) }
            Menu {
                ForEach(CaffeinePreset.all) { preset in
                    Button("\(preset.name) (\(Int(preset.mg)) mg)") { addCaffeine(preset.name, preset.mg) }
                }
                Button("Other") { addCaffeine("Caffeine", defaultCaffeineMg) }
            } label: {
                Label("Add caffeine", systemImage: "cup.and.saucer")
            }
        } header: {
            Text("Caffeine")
        } footer: {
            if !d.caffeine.isEmpty { Text("Total \(Int(d.totalCaffeineMg)) mg. Swipe left to remove.") }
        }
    }

    private var alcoholSection: some View {
        Section("Alcohol") {
            ForEach($d.alcohol) { $item in
                HStack {
                    Stepper("\(Fmt.number(item.drinks)) drink\(item.drinks == 1 ? "" : "s")",
                            value: $item.drinks, in: 0...20, step: 0.5)
                    DatePicker("Time", selection: anchored($item.time, .daytime),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            .onDelete { d.alcohol.remove(atOffsets: $0) }
            Button {
                d.alcohol.append(AlcoholItem(time: defaultItemTime(hour: 19), drinks: 1))
            } label: {
                Label("Add drink", systemImage: "wineglass")
            }
        }
    }

    private var napSection: some View {
        Section("Naps") {
            ForEach($d.naps) { $item in
                HStack {
                    Stepper(Fmt.hm(Double(item.minutes)), value: $item.minutes, in: 5...300, step: 5)
                    DatePicker("Start", selection: anchored($item.start, .daytime),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            .onDelete { d.naps.remove(atOffsets: $0) }
            Button {
                d.naps.append(NapItem(start: defaultItemTime(hour: 15), minutes: 20))
            } label: {
                Label("Add nap", systemImage: "bed.double")
            }
        }
    }

    private var morningSection: some View {
        Section("In the morning") {
            VStack(alignment: .leading) {
                Text("How rested did you feel? (1 = not at all, 5 = fully)")
                    .font(.subheadline)
                Picker("Rested", selection: $d.rested) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            severityPicker("Grogginess", $d.grogginess)
        }
    }

    private var daySection: some View {
        Section {
            severityPicker("Daytime sleepiness", $d.daytimeSleepiness)
            severityPicker("Dizziness", $d.dizziness)
            TextField("Other side effects", text: $d.otherEffects, axis: .vertical)
        } header: {
            Text("During the day")
        } footer: {
            Text("You can come back and fill this in later in the day.")
        }
    }

    private func severityPicker(_ title: String, _ value: Binding<Severity>) -> some View {
        Picker(title, selection: value) {
            ForEach(Severity.allCases) { Text($0.label).tag($0) }
        }
    }

    // MARK: Helpers

    private var nightBinding: Binding<Date> {
        Binding(
            get: { d.night },
            set: { newValue in
                d.night = Calendar.current.startOfDay(for: newValue)
                d.reanchor()
            }
        )
    }

    /// Wraps a time binding so whatever clock time is picked lands on the
    /// correct side of midnight for this night.
    private func anchored(_ source: Binding<Date>, _ anchor: TimeAnchor) -> Binding<Date> {
        Binding(
            get: { source.wrappedValue },
            set: { source.wrappedValue = TimeResolver.resolve($0, night: d.night, anchor: anchor) }
        )
    }

    private func defaultItemTime(hour: Int) -> Date {
        TimeResolver.at(hour: hour, minute: 0, night: d.night, anchor: .daytime)
    }

    private func addCaffeine(_ label: String, _ mg: Double) {
        d.caffeine.append(CaffeineItem(time: defaultItemTime(hour: 9), label: label, mg: mg))
    }

    @MainActor
    private func save() {
        let target: DiaryEntry
        if let entry {
            entry.apply(d)
            target = entry
        } else {
            target = DiaryEntry(draft: d)
            context.insert(target)
        }
        try? context.save()

        let draft = d
        let id = target.entryID
        let shouldWriteSleep = self.writeSleep
        let manager = self.health
        let ctx = self.context
        Task { @MainActor in
            do {
                try await manager.sync(draft, entryID: id, writeNaps: shouldWriteSleep,
                                       writeGrogginess: target.morningConfirmedAt != nil || draft.grogginess != .notPresent)
                target.healthSyncedAt = Date()
                target.healthSyncError = nil
            } catch {
                target.healthSyncError = error.localizedDescription
            }
            try? ctx.save()
        }
        dismiss()
    }
}
