import SwiftUI

struct ExportView: View {
    let entries: [DiaryEntry]

    @Environment(\.dismiss) private var dismiss
    @Environment(HealthManager.self) private var health
    @AppStorage(SettingsKeys.preferredSource) private var preferredSource = ""

    @State private var days = 28
    @State private var files: [URL] = []
    @State private var working = false
    @State private var errorText: String?

    private var selected: [DiaryEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: today) ?? .distantPast
        return entries.filter { $0.night >= cutoff }.sorted { $0.night < $1.night }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Period", selection: $days) {
                        Text("Last 7 nights").tag(7)
                        Text("Last 2 weeks").tag(14)
                        Text("Last 4 weeks").tag(28)
                        Text("Last 8 weeks").tag(56)
                        Text("Everything").tag(36500)
                    }
                    .onChange(of: days) { files = [] }
                } footer: {
                    Text("\(selected.count) night\(selected.count == 1 ? "" : "s") in this period.")
                }

                Section {
                    Button {
                        Task { await build() }
                    } label: {
                        if working { ProgressView() } else { Text("Create PDF and spreadsheet") }
                    }
                    .disabled(working || selected.isEmpty)
                } footer: {
                    Text("The PDF is a one-page-wide table for your doctor with averages at the top. The CSV opens in Numbers, Excel or Google Sheets.")
                }

                if !files.isEmpty {
                    Section("Ready to share") {
                        ForEach(files, id: \.self) { url in
                            ShareLink(item: url) {
                                Label(url.lastPathComponent,
                                      systemImage: url.pathExtension == "pdf" ? "doc.richtext" : "tablecells")
                            }
                        }
                    }
                }

                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle("Export for doctor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @MainActor
    private func build() async {
        working = true
        defer { working = false }
        var rows: [ExportRow] = []
        for entry in selected {
            let d = entry.draft
            let summaries = (try? await health.sleepSummaries(forNight: d.night)) ?? []
            rows.append(ExportRow(draft: d, health: NightSleepSummary.pick(from: summaries,
                                                                            preferred: preferredSource)))
        }
        do {
            files = try Exporter.write(rows: rows)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
