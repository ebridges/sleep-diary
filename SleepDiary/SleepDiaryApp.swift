import SwiftUI
import SwiftData

@main
struct SleepDiaryApp: App {
    @State private var health = HealthManager()

    var body: some Scene {
        WindowGroup {
            EntryListView()
                .environment(health)
        }
        .modelContainer(for: DiaryEntry.self)
    }
}
