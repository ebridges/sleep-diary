import SwiftUI
import SwiftData

@main
struct SleepDiaryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var health = HealthManager()

    init() {
        MedicationSettings.migrate()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(health)
        }
        .modelContainer(for: [DiaryEntry.self, SymptomEntry.self])
    }
}
