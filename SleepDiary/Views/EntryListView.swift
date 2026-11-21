import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthManager.self) private var health
    @Query(sort: \DiaryEntry.night, order: .reverse) private var entries: [DiaryEntry]
    @AppStorage(SettingsKeys.defaultMedicationName) private var defaultMedicationName = ""

    @State private var showingNew = false
    @State private var showingSettings = false
    @State private var showingExport = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    NavigationLink {
                        EntryEditorView(entry: entry)
                    } label: {
                        EntryRow(entry: entry)
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No nights logged yet",
                        systemImage: "moon.zzz",
                        description: Text("Tap + each morning to log last night.")
                    )
                }
            }
            .navigationTitle("Sleep Diary")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingExport = true } label: { Image(systemName: "square.and.arrow.up") }
                        .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) {
                NavigationStack {
                    EntryEditorView(
                        entry: nil,
                        newDraft: EntryDraft.new(after: entries.first?.draft,
                                                 defaultMedicationName: defaultMedicationName)
                    )
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingExport) { ExportView(entries: entries) }
            .task { await health.requestAuthorization() }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let entry = entries[index]
            let id = entry.entryID
            context.delete(entry)
            Task { try? await health.deleteSamples(for: id) }
        }
        try? context.save()
    }
}

struct EntryRow: View {
    let entry: DiaryEntry

    var body: some View {
        let d = entry.draft
        let stars = max(0, min(5, d.rested))
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Fmt.night(d.night)).font(.headline)
                Spacer()
                Text(String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars))
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Text("\(Fmt.time(d.bedTime)) to \(Fmt.time(d.finalWake)), \(Fmt.hm(d.totalSleepMinutes)) asleep, \(d.awakenings) wakes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if d.tookMedication {
                Text("\(d.medicationName) \(d.medicationDose) at \(Fmt.time(d.medicationTime))")
                    .font(.caption)
            }
            if entry.healthSyncError != nil {
                Label("Not saved to Health. Open and save again.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}
