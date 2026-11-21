import SwiftUI

/// Side-by-side: what you wrote in the diary vs. what Apple Health recorded.
struct HealthComparisonView: View {
    let draft: EntryDraft

    @Environment(HealthManager.self) private var health
    @AppStorage(SettingsKeys.preferredSource) private var preferredSource = ""
    @State private var summaries: [NightSleepSummary] = []
    @State private var selectedID = ""
    @State private var loading = false
    @State private var errorText: String?

    private var current: NightSleepSummary? {
        summaries.first { $0.sourceID == selectedID } ?? summaries.first
    }

    var body: some View {
        Section {
            if loading {
                ProgressView()
            } else if let errorText {
                Text(errorText).foregroundStyle(.red)
            } else if summaries.isEmpty {
                Text("No sleep from Apple Watch, AutoSleep or other apps found in Health for this night.")
                    .foregroundStyle(.secondary)
            } else {
                if summaries.count > 1 {
                    Picker("Source", selection: $selectedID) {
                        ForEach(summaries) { Text($0.sourceName).tag($0.sourceID) }
                    }
                }
                if let s = current { grid(s) }
            }
            Button("Refresh from Health") { Task { await load() } }
        } header: {
            Text("Diary vs. Apple Health")
        } footer: {
            Text("Health counts a wake as any gap of 2+ minutes between sleep segments, so it usually finds more wakes than you remember. That difference is normal and useful to show a doctor.")
        }
        .task(id: draft.night) { await load() }
    }

    private func grid(_ s: NightSleepSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("")
                Text("Diary").bold()
                Text(s.sourceName).bold().lineLimit(1)
            }
            Divider()
            row("In bed", Fmt.time(draft.bedTime), Fmt.time(s.inBedStart))
            row("Asleep", Fmt.time(draft.sleepOnset), Fmt.time(s.sleepOnset))
            row("To fall asleep", Fmt.hm(draft.latencyMinutes), Fmt.hm(s.latencyMinutes))
            row("Wakes", "\(draft.awakenings)", "\(s.awakenings)")
            row("Awake", Fmt.hm(Double(draft.minutesAwake)), Fmt.hm(s.awakeMinutes))
            row("Final wake", Fmt.time(draft.finalWake), Fmt.time(s.finalWake))
            row("Total sleep", Fmt.hm(draft.totalSleepMinutes), Fmt.hm(s.asleepMinutes))
            if s.hasStages {
                Divider()
                row("Deep / REM", "", "\(Fmt.hm(s.deepMinutes)) / \(Fmt.hm(s.remMinutes))")
            }
        }
        .font(.subheadline)
    }

    private func row(_ label: String, _ diary: String, _ recorded: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(diary)
            Text(recorded)
        }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            summaries = try await health.sleepSummaries(forNight: draft.night)
            errorText = nil
            selectedID = NightSleepSummary.pick(from: summaries, preferred: preferredSource)?.sourceID ?? ""
        } catch {
            errorText = error.localizedDescription
        }
    }
}
