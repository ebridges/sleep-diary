import SwiftUI

/// Check-in step 2: confirm or correct what Apple Health recorded for the night.
/// Corrections stay in the app; nothing here is written to Health.
struct LastNightView: View {
    @Bindable var checkIn: CheckIn
    let onDone: () -> Void

    @AppStorage(SettingsKeys.writeSleepToHealth) private var writeNaps = false
    @State private var showingAddWake = false
    @State private var saving = false

    private var current: NightSleepSummary? { checkIn.current }

    var body: some View {
        StepScaffold(step: .lastNight, title: "Last night",
                     subtitle: "Here's what Apple Health recorded. Correct anything that doesn't match how it felt.") {
            nightCard
            fallingAsleepCard
            wakeUpsCard
            wakingUpCard
            ForEach(problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
            }
            Button("Confirm last night") {
                saving = true
                Task {
                    await checkIn.confirm(.lastNight, writeNaps: writeNaps)
                    saving = false
                    onDone()
                }
            }
            .buttonStyle(WideButtonStyle())
            .disabled(saving)
        }
        .sheet(isPresented: $showingAddWake) {
            AddWakeSheet(night: checkIn.night, suggested: suggestedWakeTime) { checkIn.d.addedWakes.append($0) }
        }
    }

    // MARK: Night card

    private var nightCard: some View {
        Card(spacing: 14) {
            HStack {
                CardLabel(text: nightRangeText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                sourcePicker
            }
            if checkIn.sleepLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 130)
            } else if let s = current {
                HypnogramView(summary: s)
                HStack {
                    stat("Asleep", Fmt.hm(s.asleepMinutes))
                    Spacer()
                    stat("Awake", Fmt.hm(s.inBedSpanMinutes.map { max(0, $0 - s.asleepMinutes) }))
                    Spacer()
                    stat("In bed", Fmt.hm(s.inBedSpanMinutes))
                }
                .font(.system(size: 13))
            } else {
                Text(checkIn.sleepError ?? "No sleep from Apple Watch, AutoSleep or other apps found in Health for this night. You can still enter your own times below.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private var nightRangeText: String {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: checkIn.night) ?? checkIn.night
        return "\(Fmt.shortDay(checkIn.night)) → \(Fmt.shortDay(next))"
    }

    @ViewBuilder
    private var sourcePicker: some View {
        if checkIn.summaries.count > 1 {
            Menu {
                Picker("Source", selection: Binding(get: { current?.sourceID ?? "" },
                                                    set: { checkIn.selectSource($0) })) {
                    ForEach(checkIn.summaries) { Text($0.sourceName).tag($0.sourceID) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(current?.sourceName ?? "Source").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
            }
        } else if let s = current {
            Text(s.sourceName)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        (Text(label + " ").foregroundStyle(Theme.secondary) + Text(value).bold().foregroundStyle(Theme.text))
    }

    // MARK: Falling asleep

    private var fallingAsleepCard: some View {
        Card {
            Text("Falling asleep").font(Theme.cardTitleFont)
            TimeRow(title: "Got into bed", hint: bedHint, time: anchored(\.bedTime, .evening))
            TimeRow(title: "Fell asleep", hint: onsetHint, time: anchored(\.sleepOnset, .evening))
            FlowRow {
                ForEach(FallAsleepFeel.allCases) { feel in
                    Chip(title: feel.label, selected: checkIn.d.fallAsleepFeel == feel) {
                        checkIn.d.fallAsleepFeel = checkIn.d.fallAsleepFeel == feel ? nil : feel
                    }
                }
            }
            if checkIn.d.fallAsleepFeel == .tookLonger {
                Text("Set Fell asleep to when you think you dropped off.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private var bedHint: String? {
        guard let bed = current?.inBedSpanStart else { return nil }
        return "Health: \(Fmt.time(bed))"
    }

    private var onsetHint: String? {
        guard let s = current, let onset = s.sleepOnset else { return nil }
        if let bed = s.inBedSpanStart, onset.timeIntervalSince(bed) < 60 {
            return "Health: same minute you got into bed"
        }
        return "Health: \(Fmt.time(onset))"
    }

    // MARK: Wake-ups

    private var wakeUpsCard: some View {
        let wakes = current?.wakes ?? []
        let remembered = wakes.filter(checkIn.isRemembered).count
        return Card(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Wake-ups").font(Theme.cardTitleFont)
                Spacer()
                if !wakes.isEmpty {
                    Text("\(remembered) of \(wakes.count) remembered")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }
            if current != nil {
                Text(wakes.isEmpty
                     ? "Health found no wake-ups of 2 minutes or more."
                     : "Health found \(wakes.count) wake-up\(wakes.count == 1 ? "" : "s") of 2 minutes or more. Mark the ones you remember.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(Array(wakes.enumerated()), id: \.offset) { i, wake in
                HStack(spacing: 12) {
                    NumberBadge(text: "\(i + 1)")
                    wakeText(time: wake.start, detail: "awake \(Fmt.hm(wake.duration / 60))")
                    Chip(title: "I remember", selected: checkIn.isRemembered(wake)) { checkIn.toggleRemembered(wake) }
                }
                .frame(minHeight: 52)
            }
            if let n = current?.briefStirrings, n > 0 {
                Text("Plus \(n) brief stirring\(n == 1 ? "" : "s") under 2 minutes, not counted.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(checkIn.d.addedWakes) { added in
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 24, height: 24)
                        .background(Theme.cardRaised, in: Circle())
                    wakeText(time: added.start, detail: "awake \(Fmt.hm(Double(added.minutes))), added by you")
                    DeleteButton(label: "Remove wake-up at \(Fmt.time(added.start))") {
                        checkIn.d.addedWakes.removeAll { $0.id == added.id }
                    }
                }
                .frame(minHeight: 52)
            }
            Button {
                showingAddWake = true
            } label: {
                Label("Add a wake-up Health missed", systemImage: "plus")
            }
            .buttonStyle(WideButtonStyle(primary: false))
            .padding(.top, 6)
        }
    }

    private func wakeText(time: Date, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.time(time)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestedWakeTime: Date {
        let d = checkIn.d
        return d.sleepOnset.addingTimeInterval(max(0, d.finalWake.timeIntervalSince(d.sleepOnset)) / 2)
    }

    // MARK: Waking up

    private var wakingUpCard: some View {
        Card {
            Text("Waking up").font(Theme.cardTitleFont)
            TimeRow(title: "Woke for good",
                    hint: current?.finalWake.map { "Health: last sleep ended \(Fmt.time($0))" },
                    time: anchored(\.finalWake, .morning))
            TimeRow(title: "Got out of bed",
                    time: Binding(
                        get: { checkIn.d.outOfBed },
                        set: { checkIn.d.outOfBed = $0.map { TimeResolver.resolve($0, night: checkIn.night, anchor: .morning) } }
                    ),
                    defaultTime: checkIn.d.finalWake)
        }
    }

    // MARK: Checks

    private var problems: [String] {
        let d = checkIn.d
        var p: [String] = []
        if d.sleepOnset < d.bedTime { p.append("Fell asleep is before you got into bed.") }
        if d.finalWake <= d.sleepOnset { p.append("Woke for good is before you fell asleep.") }
        if let out = d.outOfBed, out < d.finalWake { p.append("Got out of bed is before you woke for good.") }
        return p
    }

    /// A binding to one of the draft's times that places whatever clock time is
    /// picked on the correct side of midnight for this night.
    private func anchored(_ key: WritableKeyPath<EntryDraft, Date>, _ anchor: TimeAnchor) -> Binding<Date?> {
        Binding(
            get: { checkIn.d[keyPath: key] },
            set: { newValue in
                if let newValue {
                    checkIn.d[keyPath: key] = TimeResolver.resolve(newValue, night: checkIn.night, anchor: anchor)
                }
            }
        )
    }
}

/// Lays chips out left to right, wrapping onto new lines as needed.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Add a wake-up the user remembers that Health didn't record.
struct AddWakeSheet: View {
    let night: Date
    let suggested: Date
    let onAdd: (AddedWake) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var minutes = 10

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Woke at", selection: $time, displayedComponents: .hourAndMinute)
                Stepper("Awake about \(Fmt.hm(Double(minutes)))", value: $minutes, in: 1...240,
                        step: minutes < 10 ? 1 : 5)
            }
            .navigationTitle("Add a wake-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(AddedWake(start: TimeResolver.resolve(time, night: night, anchor: .evening),
                                        minutes: minutes))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { time = suggested }
    }
}
