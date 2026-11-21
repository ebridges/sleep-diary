import SwiftUI

/// Check-in step 3: caffeine, alcohol and naps on the day before the night.
struct YesterdayView: View {
    @Bindable var checkIn: CheckIn
    let onDone: () -> Void

    @AppStorage(SettingsKeys.writeSleepToHealth) private var writeNaps = false
    @AppStorage(SettingsKeys.defaultCaffeineMg) private var otherCaffeineMg = 95.0
    @State private var saving = false

    private static let drinkKinds = ["Beer", "Wine", "Spirits"]
    private static let otherCaffeineLabel = "Other"

    var body: some View {
        StepScaffold(step: .yesterday, title: "Yesterday",
                     subtitle: "\(Fmt.longDay(checkIn.night)), before bed") {
            Card {
                CardLabel(text: "Your day")
                DayTimeline(draft: checkIn.d)
                Text("What you add appears on this line, so you can see its timing against bedtime.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
            caffeineCard
            alcoholCard
            napCard
            Button("Next") {
                saving = true
                Task {
                    await checkIn.confirm(.yesterday, writeNaps: writeNaps)
                    saving = false
                    onDone()
                }
            }
            .buttonStyle(WideButtonStyle())
            .disabled(saving)
        }
        .task { await checkIn.loadHealthCaffeine() }
    }

    // MARK: Caffeine

    private var caffeineCard: some View {
        let fromHealth = checkIn.d.caffeine.filter(\.isFromHealth)
        return Card {
            IconTitle(title: "Caffeine", systemImage: "cup.and.saucer")
            Text(fromHealth.isEmpty
                 ? "Nothing in Apple Health for \(Fmt.weekday(checkIn.night)). Tap what you had, then set the time."
                 : "From Apple Health. Tap to add anything else you had.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
            ForEach(checkIn.d.caffeine) { item in
                if item.isFromHealth {
                    itemRow(title: "\(Int(item.mg)) mg", detail: item.label) {
                        Text(Fmt.time(item.time)).monospacedDigit().foregroundStyle(Theme.secondary)
                    }
                } else if item.label == Self.otherCaffeineLabel {
                    // A drink without a preset: set the caffeine directly.
                    itemRow(title: "Other, \(Int(item.mg)) mg", detail: CaffeineGuide.describe(item.mg)) {
                        Stepper("\(Int(item.mg)) mg", value: binding(\.caffeine, item).mg, in: 10...1000, step: 10)
                            .labelsHidden()
                        Spacer()
                        timePicker(binding(\.caffeine, item).time)
                        DeleteButton(label: "Remove \(item.label)") { remove(\.caffeine, item.id) }
                    }
                } else {
                    // A preset drink: count servings; the mg follows.
                    itemRow(title: item.label, detail: "\(Int(item.mg)) mg in total") {
                        Stepper("\(Fmt.number(item.servingCount))", value: servingsBinding(item), in: 0.5...10, step: 0.5)
                            .labelsHidden()
                        Text("× \(Fmt.number(item.servingCount))").monospacedDigit().frame(width: 44, alignment: .trailing)
                        timePicker(binding(\.caffeine, item).time)
                        DeleteButton(label: "Remove \(item.label)") { remove(\.caffeine, item.id) }
                    }
                }
            }
            FlowRow {
                ForEach(CaffeinePreset.all) { preset in
                    Chip(title: "\(preset.name) · \(Int(preset.mg)) mg", selected: false) {
                        addCaffeine(preset.name, preset.mg)
                    }
                }
                Chip(title: "Other", selected: false) { addCaffeine(Self.otherCaffeineLabel, otherCaffeineMg) }
            }
            Text("Tap a drink to add it, then set the time. Use − / + for more than one at the same time. Drip coffee has about 40 mg per 100 ml; use Other for anything else.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            Chip(title: "None yesterday", selected: checkIn.d.caffeine.isEmpty) {
                checkIn.d.caffeine.removeAll { !$0.isFromHealth }
            }
        }
    }

    private func addCaffeine(_ label: String, _ mg: Double) {
        checkIn.d.caffeine.append(CaffeineItem(time: defaultTime(hour: 9), label: label, mg: mg))
        checkIn.d.caffeine.sort { $0.time < $1.time }
    }

    // MARK: Alcohol

    private var alcoholCard: some View {
        Card {
            IconTitle(title: "Alcohol", systemImage: "wineglass")
            FlowRow {
                Chip(title: "None", selected: checkIn.d.alcohol.isEmpty) { checkIn.d.alcohol = [] }
                ForEach(Self.drinkKinds, id: \.self) { kind in
                    Chip(title: kind, selected: false) {
                        checkIn.d.alcohol.append(AlcoholItem(time: defaultTime(hour: 19), drinks: 1, kind: kind))
                    }
                }
            }
            ForEach(checkIn.d.alcohol) { item in
                itemRow(title: item.kind ?? "Drink", detail: nil) {
                    Stepper("\(Fmt.number(item.drinks))", value: binding(\.alcohol, item).drinks, in: 0.5...20, step: 0.5)
                        .labelsHidden()
                    Text("\(Fmt.number(item.drinks)) drink\(item.drinks == 1 ? "" : "s")")
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                    timePicker(binding(\.alcohol, item).time)
                    DeleteButton(label: "Remove \(item.kind ?? "drink")") { remove(\.alcohol, item.id) }
                }
            }
            Text("Count standard drinks, as Apple Health does: one is a 12 oz (355 ml) beer at 5%, a 5 oz (150 ml) glass of wine at 12%, or a 1.5 oz (44 ml) shot of spirits. A large glass of wine or a strong beer can be 1.5 to 2.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
        }
    }

    // MARK: Nap

    private var napCard: some View {
        Card {
            IconTitle(title: "Nap", systemImage: "bed.double")
            FlowRow {
                Chip(title: "No nap", selected: checkIn.d.naps.isEmpty) { checkIn.d.naps = [] }
                Chip(title: "Add a nap", selected: false) {
                    checkIn.d.naps.append(NapItem(start: defaultTime(hour: 15), minutes: 20))
                }
            }
            ForEach(checkIn.d.naps) { nap in
                itemRow(title: "Nap", detail: nil) {
                    Stepper(Fmt.hm(Double(nap.minutes)), value: binding(\.naps, nap).minutes, in: 5...300, step: 5)
                        .labelsHidden()
                    Text(Fmt.hm(Double(nap.minutes))).monospacedDigit().frame(width: 56, alignment: .trailing)
                    timePicker(binding(\.naps, nap).start)
                    DeleteButton(label: "Remove nap") { remove(\.naps, nap.id) }
                }
            }
            Text(writeNaps
                 ? "Naps are saved to Apple Health as sleep."
                 : "Naps stay in the diary. Turn on \"Write naps to Health\" in Settings to save them as sleep.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
        }
    }

    // MARK: Helpers

    /// A binding to one item of a draft list, found by ID each time.
    ///
    /// Rows don't use `ForEach($list)`: deleting from a closure that reads the
    /// row's binding accesses `checkIn.d` while it's being modified, and Swift's
    /// exclusivity check stops the app.
    private func binding<T: Identifiable>(_ list: WritableKeyPath<EntryDraft, [T]>, _ item: T) -> Binding<T> {
        let id = item.id
        return Binding(
            get: { checkIn.d[keyPath: list].first { $0.id == id } ?? item },
            set: { newValue in
                if let i = checkIn.d[keyPath: list].firstIndex(where: { $0.id == id }) {
                    checkIn.d[keyPath: list][i] = newValue
                }
            }
        )
    }

    private func servingsBinding(_ item: CaffeineItem) -> Binding<Double> {
        let row = binding(\.caffeine, item)
        return Binding(
            get: { row.wrappedValue.servingCount },
            set: { n in
                var updated = row.wrappedValue
                updated.setServings(n)
                row.wrappedValue = updated
            }
        )
    }

    private func remove<T: Identifiable>(_ list: WritableKeyPath<EntryDraft, [T]>, _ id: T.ID) {
        checkIn.d[keyPath: list].removeAll { $0.id == id }
    }

    private func itemRow<Trailing: View>(title: String, detail: String?,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if let detail {
                        Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: 8) { trailing() }
        }
        .padding(.vertical, 4)
    }

    private func timePicker(_ time: Binding<Date>) -> some View {
        DatePicker("Time", selection: Binding(
            get: { time.wrappedValue },
            set: { time.wrappedValue = TimeResolver.resolve($0, night: checkIn.night, anchor: .daytime) }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
    }

    private func defaultTime(hour: Int) -> Date {
        TimeResolver.at(hour: hour, minute: 0, night: checkIn.night, anchor: .daytime)
    }
}

/// The day from 6 am to bedtime, with caffeine, alcohol and naps marked on it.
struct DayTimeline: View {
    let draft: EntryDraft

    private var domain: (start: Date, end: Date) {
        let start = TimeResolver.at(hour: 6, minute: 0, night: draft.night, anchor: .daytime)
        let elevenPM = TimeResolver.at(hour: 23, minute: 0, night: draft.night, anchor: .daytime)
        return (start, max(elevenPM, draft.bedTime.addingTimeInterval(30 * 60)))
    }

    var body: some View {
        Canvas { context, size in
            let d = domain
            let span = d.end.timeIntervalSince(d.start)
            func x(_ date: Date) -> CGFloat {
                CGFloat(min(max(0, date.timeIntervalSince(d.start) / span), 1)) * size.width
            }
            let barY: CGFloat = 26

            context.fill(Path(roundedRect: CGRect(x: 0, y: barY, width: size.width, height: 6), cornerRadius: 3),
                         with: .color(Theme.cardRaised))

            for nap in draft.naps {
                let rect = CGRect(x: x(nap.start), y: barY, width: max(3, x(nap.end) - x(nap.start)), height: 6)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Theme.core))
            }
            for item in draft.caffeine {
                dot(&context, at: x(item.time), y: barY + 3, color: Theme.accent)
            }
            for item in draft.alcohol {
                dot(&context, at: x(item.time), y: barY + 3, color: Theme.rem)
            }

            let bx = x(draft.bedTime)
            context.fill(Path(CGRect(x: bx - 1, y: 16, width: 2, height: 26)), with: .color(Theme.rem))
            context.draw(Text("bed \(Fmt.time(draft.bedTime))").font(.system(size: 11)).foregroundColor(Theme.rem),
                         at: CGPoint(x: min(bx, size.width - 30), y: 6))

            var hour = 6
            while hour <= 24 {
                let t = TimeResolver.at(hour: hour % 24, minute: 0, night: draft.night, anchor: .daytime)
                if t <= d.end {
                    let label = "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 || hour == 24 ? "a" : "p")"
                    context.draw(Text(label).font(.system(size: 11)).foregroundColor(Theme.secondary),
                                 at: CGPoint(x: min(max(10, x(t)), size.width - 10), y: 48))
                }
                hour += 3
            }
        }
        .frame(height: 56)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private func dot(_ context: inout GraphicsContext, at x: CGFloat, y: CGFloat, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)), with: .color(color))
    }

    private var accessibilityText: String {
        var parts = ["Bed at \(Fmt.time(draft.bedTime))"]
        if !draft.caffeine.isEmpty { parts.append("\(draft.caffeine.count) caffeine") }
        if !draft.alcohol.isEmpty { parts.append("\(draft.alcohol.count) drinks") }
        if !draft.naps.isEmpty { parts.append("\(draft.naps.count) naps") }
        return parts.joined(separator: ", ")
    }
}
