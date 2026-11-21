#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthKit

/// The Simulator has no sleep data, so debug builds there show a made-up night
/// from two sources: one with stages (like Apple Watch) and one without (like AutoSleep).
enum SampleNight {
    static func dose(forNight night: Date, name: String) -> MedicationLookup {
        let time = TimeResolver.at(hour: 21, minute: 30, night: night, anchor: .evening)
        return .found(MedicationDose(name: name.isEmpty ? "Sample medication" : name, amount: "1 tablet", time: time))
    }

    static func summaries(forNight night: Date) -> [NightSleepSummary] {
        let base = Calendar.current.startOfDay(for: night)
        func at(_ h: Int, _ m: Int) -> Date {
            let day = h < 12 ? 1 : 0
            return Calendar.current.date(byAdding: DateComponents(day: day, hour: h, minute: m), to: base) ?? base
        }

        // Awake gaps (start, minutes). The 1-minute ones are brief stirrings.
        let gaps: [(Date, Double)] = [
            (at(22, 50), 1), (at(23, 40), 1), (at(0, 18), 9), (at(1, 13), 3),
            (at(1, 43), 10), (at(2, 20), 1), (at(2, 54), 15), (at(3, 13), 5),
        ]
        let onset = at(21, 52)
        let end = at(4, 1)

        var blocks: [(Date, Date)] = []
        var cursor = onset
        for (start, minutes) in gaps {
            blocks.append((cursor, start))
            cursor = start.addingTimeInterval(minutes * 60)
        }
        blocks.append((cursor, end))

        let core = HKCategoryValueSleepAnalysis.asleepCore.rawValue
        let deep = HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        let rem = HKCategoryValueSleepAnalysis.asleepREM.rawValue
        let cycle: [(Int, Double)] = [(core, 12), (deep, 18), (core, 15), (rem, 20)]

        var staged: [NightSleepSummary.RawSample] = []
        var plain: [NightSleepSummary.RawSample] = []
        var step = 0
        for (start, stop) in blocks {
            plain.append(.init(start: start, end: stop, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue))
            var t = start
            while t < stop {
                let (value, minutes) = cycle[step % cycle.count]
                let next = min(stop, t.addingTimeInterval(minutes * 60))
                staged.append(.init(start: t, end: next, value: value))
                t = next
                step += 1
            }
        }
        let inBed = HKCategoryValueSleepAnalysis.inBed.rawValue
        plain.append(.init(start: at(21, 40), end: at(4, 20), value: inBed))

        return [
            NightSleepSummary.summarizeOne(sourceID: "sample.watch", sourceName: "Apple Watch (sample)", samples: staged),
            NightSleepSummary.summarizeOne(sourceID: "sample.autosleep", sourceName: "AutoSleep (sample)", samples: plain),
        ].compactMap { $0 }
    }
}
#endif
