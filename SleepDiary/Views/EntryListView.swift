import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthManager.self) private var health
    @Query(sort: \DiaryEntry.night, order: .reverse) private var entries: [DiaryEntry]
    @AppStorage(SettingsKeys.defaultMedicationName) private var defaultMedicationName = ""

    @State private var showingNew = false
    @State private var showingExport = false

    /// All nights, newest first. Pushed from Home.
    var body: some View {
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
                        description: Text("Finish a morning check-in and it appears here.")
                    )
                }
            }
            .navigationTitle("All nights")
            .toolbar {
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
            .sheet(isPresented: $showingExport) { ExportView(entries: entries) }
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
