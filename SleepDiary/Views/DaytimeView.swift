import SwiftUI
import SwiftData

/// Log a symptom when you notice it. Each entry has its own time and is
/// written to Health as a symptom with the same severity.
struct DaytimeView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthManager.self) private var health
    @Query(sort: \SymptomEntry.time, order: .reverse) private var allEntries: [SymptomEntry]

    @State private var kind: SymptomKind?
    @State private var otherName = ""
    @State private var severity: Severity?
    @State private var time = Date()
    @State private var timeEdited = false
    @State private var saving = false
    @State private var status: String?
    @State private var statusSavedToHealth = false

    private var today: [SymptomEntry] {
        allEntries.filter { Calendar.current.isDateInToday($0.time) }
    }

    private var canSave: Bool {
        guard let kind, severity != nil, !saving else { return false }
        return kind != .other || !otherName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How do you feel now?").font(Theme.headingFont)
                    Text("Log it when you notice it. Each entry gets its own time.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                }
                Card {
                    Text("What are you noticing?").font(Theme.cardTitleFont)
                    // A fixed grid, so the check mark on the selected item doesn't rewrap the
                    // row and move the controls below it under the user's finger.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                        ForEach(SymptomKind.allCases) { k in
                            gridButton(k.label, selected: kind == k, checkmark: true) { kind = k }
                        }
                    }
                    if kind == .other {
                        TextField("What is it?", text: $otherName)
                            .padding(12)
                            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Card {
                    Text(severityQuestion).font(Theme.cardTitleFont)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                        ForEach(Severity.allCases) { s in
                            gridButton(s.label, selected: severity == s) { severity = s }
                        }
                    }
                    // Swapped in place of the usual line so nothing above moves.
                    Text(kind != nil && kind?.healthType == nil
                         ? "Health has no type for this, so it stays in Sleep Diary."
                         : "Same scale Apple Health uses for symptoms.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                Card {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("When").font(.system(size: 15, weight: .medium))
                            Text(timeEdited ? "Set by you" : "Now. Tap to set an earlier time")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        DatePicker("When", selection: Binding(
                            get: { time },
                            set: { time = min($0, Date()); timeEdited = true }
                        ), in: ...Date(), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    }
                    .frame(minHeight: 44)
                }
                Button("Save entry", action: save)
                    .buttonStyle(WideButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                if let status {
                    Label(status, systemImage: statusSavedToHealth ? "checkmark.circle" : "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(statusSavedToHealth ? Theme.success : Theme.secondary)
                }
                todayCard
            }
            .padding(20)
        }
        .nightStyle()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !timeEdited { time = Date() } }
    }

    private func gridButton(_ title: String, selected: Bool, checkmark: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if checkmark && selected {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                }
                Text(title)
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(selected ? Theme.onAccent : Theme.text)
            .background(selected ? Theme.accent : Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var severityQuestion: String {
        guard let kind else { return "How strong is it?" }
        let name = kind == .other ? (otherName.isEmpty ? "it" : otherName.lowercased()) : "the \(kind.label.lowercased())"
        return "How strong is \(name)?"
    }

    private var todayCard: some View {
        Card(spacing: 4) {
            CardLabel(text: "Today, \(Fmt.shortDay(Date()))")
            if today.isEmpty {
                Text("Nothing logged yet today.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .frame(minHeight: 40)
            }
            ForEach(today) { entry in
                HStack(spacing: 12) {
                    Text(Fmt.time(entry.time))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name).font(.system(size: 15, weight: .semibold))
                        if let error = entry.healthSyncError {
                            Text("Not saved to Health: \(error)")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Spacer()
                    Text(entry.severity.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                    DeleteButton(label: "Delete \(entry.name) at \(Fmt.time(entry.time))") { delete(entry) }
                }
                .frame(minHeight: 48)
            }
            Text("Each entry is also saved to Apple Health as a symptom, with the same rating. Sleepiness and grogginess are saved as Fatigue; dry mouth and other effects stay in Sleep Diary.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 4)
        }
    }

    private func save() {
        guard let kind, let severity else { return }
        let entry = SymptomEntry(time: timeEdited ? time : Date(), kind: kind,
                                 otherName: kind == .other ? otherName.trimmingCharacters(in: .whitespaces) : "",
                                 severity: severity)
        context.insert(entry)
        try? context.save()
        saving = true
        Task {
            do {
                let result = try await health.sync(entry)
                entry.healthSyncedAt = Date()
                entry.healthSyncError = nil
                status = "\(entry.name) logged. \(result)."
                statusSavedToHealth = result.hasPrefix("Saved")
            } catch {
                entry.healthSyncError = error.localizedDescription
                status = "\(entry.name) logged in Sleep Diary."
                statusSavedToHealth = false
            }
            try? context.save()
            saving = false
            self.kind = nil
            self.severity = nil
            otherName = ""
            timeEdited = false
            time = Date()
        }
    }

    private func delete(_ entry: SymptomEntry) {
        let id = entry.entryID
        context.delete(entry)
        try? context.save()
        Task { try? await health.deleteSamples(for: id) }
    }
}
