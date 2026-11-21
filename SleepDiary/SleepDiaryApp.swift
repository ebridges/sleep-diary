import SwiftUI
import SwiftData

@main
struct SleepDiaryApp: App {
    @State private var health = HealthManager()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(health)
        }
        .modelContainer(for: DiaryEntry.self)
    }
}
