import SwiftUI
import SwiftData

/// The app's first screen: last night from Health, the morning check-in steps,
/// and links to history and settings.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthManager.self) private var health
    @Query(sort: \DiaryEntry.night, order: .reverse) private var entries: [DiaryEntry]
    @Query(sort: \SymptomEntry.time, order: .reverse) private var symptoms: [SymptomEntry]
    @AppStorage(SettingsKeys.defaultMedicationName) private var medicationName = ""
    @AppStorage(SettingsKeys.preferredSource) private var preferredSource = ""

    @State private var checkIn: CheckIn?
    @State private var path: [CheckInRoute] = []
    @State private var showingSettings = false
    @State private var accessMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let checkIn {
                        header(checkIn)
                        summaryCard(checkIn)
                        stepsCard(checkIn)
                        startButton(checkIn)
                        daytimeCard
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .padding(20)
            }
            .nightStyle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(.history) } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel("All nights")
                }
            }
            .navigationDestination(for: CheckInRoute.self) { route in
                destination(route)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .task {
            await health.requestAuthorization()
            await refreshIfNeeded()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await refreshIfNeeded() } }
        }
        .onChange(of: NotificationRouter.shared.openDaytime, initial: true) {
            guard NotificationRouter.shared.openDaytime else { return }
            NotificationRouter.shared.openDaytime = false
            showingSettings = false
            path = [.daytime]
        }
    }

    // MARK: Navigation

    @ViewBuilder
    private func destination(_ route: CheckInRoute) -> some View {
        if let checkIn {
            switch route {
            case .step(.medication):
                MedicationView(checkIn: checkIn) { advance(from: .medication) }
            case .step(.lastNight):
                LastNightView(checkIn: checkIn) { advance(from: .lastNight) }
            case .step(.yesterday):
                YesterdayView(checkIn: checkIn) { advance(from: .yesterday) }
            case .step(.morning):
                MorningView(checkIn: checkIn) { advance(from: .morning) }
            case .saved:
                SavedView(checkIn: checkIn) { path = [] }
            case .history:
                EntryListView()
            case .daytime:
                DaytimeView()
            }
        }
    }

    private func advance(from step: CheckInStep) {
        guard let checkIn else { return }
        path.append(checkIn.route(after: step))
    }

    /// Starts a check-in for the most likely night, or a new one once that night changes.
    private func refreshIfNeeded() async {
        let night = TimeResolver.checkInNight()
        if let checkIn, Calendar.current.isDate(checkIn.night, inSameDayAs: night) { return }
        path = []
        let fresh = CheckIn(night: night, entries: entries, context: context, health: health,
                            defaultMedicationName: medicationName)
        checkIn = fresh
        await fresh.loadSleep(preferredSource: preferredSource)
    }

    // MARK: Sections

    private func header(_ checkIn: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting).font(Theme.headingFont)
            Text("\(Fmt.longDay(Date())) · check-in for \(Fmt.weekday(checkIn.night)) night")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private func summaryCard(_ checkIn: CheckIn) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                CardLabel(text: "Last night in Apple Health")
                Spacer()
                if let s = checkIn.current {
                    Text("\(Fmt.time(s.sleepOnset)) – \(Fmt.time(s.finalWake))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }
            if checkIn.sleepLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 90)
            } else if let s = checkIn.current {
                HStack(spacing: 20) {
                    bigStat(Fmt.hm(s.asleepMinutes), "asleep")
                    bigStat("\(s.wakes.count)", "wake-ups")
                    bigStat(Fmt.hm(s.inBedSpanMinutes.map { max(0, $0 - s.asleepMinutes) }), "awake")
                }
                HypnogramView(summary: s, compact: true)
            } else if checkIn.needsHealthAccess {
                Text("Sleep Diary doesn't have access to Apple Health yet, so it can't read last night.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                Button("Allow Health access") {
                    Task {
                        let result = await checkIn.requestHealthAccess(preferredSource: preferredSource)
                        accessMessage = HealthAccessText.message(for: result)
                    }
                }
                .buttonStyle(WideButtonStyle())
                if let accessMessage {
                    Text(accessMessage).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            } else {
                Text(checkIn.sleepError ?? "No sleep found in Health for \(Fmt.weekday(checkIn.night)) night.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func bigStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 30, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondary)
        }
    }

    private func stepsCard(_ checkIn: CheckIn) -> some View {
        Card(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Morning check-in").font(Theme.cardTitleFont)
                Spacer()
                Text(checkIn.allDone ? "Done" : "about 1 minute")
                    .font(.system(size: 13))
                    .foregroundStyle(checkIn.allDone ? Theme.success : Theme.secondary)
            }
            ForEach(CheckInStep.allCases) { step in
                Button {
                    path.append(.step(step))
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: step.systemImage)
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.rem)
                            .frame(width: 40, height: 40)
                            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title).font(.system(size: 15, weight: .semibold))
                            Text(step.detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        statusMark(done: checkIn.isDone(step))
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(checkIn.isDone(step) ? "Done" : "Not done")
            }
        }
    }

    @ViewBuilder
    private func statusMark(done: Bool) -> some View {
        if done {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 26, height: 26)
                .background(Theme.success, in: Circle())
        } else {
            Circle()
                .strokeBorder(Theme.line, lineWidth: 2)
                .frame(width: 26, height: 26)
        }
    }

    private var daytimeCard: some View {
        let todayCount = symptoms.filter { Calendar.current.isDateInToday($0.time) }.count
        return Card {
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("During the day").font(.system(size: 15, weight: .semibold))
                    Text(todayCount == 0
                         ? "Log sleepiness, dizziness or other effects when you notice them"
                         : "\(todayCount) logged today")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
            }
            Button("Log how I feel now") { path.append(.daytime) }
                .buttonStyle(WideButtonStyle(primary: false))
        }
    }

    @ViewBuilder
    private func startButton(_ checkIn: CheckIn) -> some View {
        if let next = checkIn.nextOpenStep {
            let started = CheckInStep.allCases.contains(where: checkIn.isDone)
            Button(started ? "Continue check-in" : "Start check-in") { path.append(.step(next)) }
                .buttonStyle(WideButtonStyle())
        } else {
            Button("Review check-in") { path.append(.step(.medication)) }
                .buttonStyle(WideButtonStyle(primary: false))
        }
    }
}
