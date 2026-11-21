import Foundation
import HealthKit

/// One source's view of one night (e.g. "AutoSleep" or "Apple Watch").
struct NightSleepSummary: Identifiable, Hashable {
    let sourceID: String
    let sourceName: String
    let inBedStart: Date?
    let inBedEnd: Date?
    let sleepOnset: Date?
    let finalWake: Date?
    let asleepMinutes: Double
    let awakenings: Int
    let awakeMinutes: Double
    let coreMinutes: Double
    let deepMinutes: Double
    let remMinutes: Double

    var id: String { sourceID }

    var latencyMinutes: Double? {
        guard let a = inBedStart, let b = sleepOnset, b >= a else { return nil }
        return b.timeIntervalSince(a) / 60
    }

    var hasStages: Bool { coreMinutes + deepMinutes + remMinutes > 0 }

    /// Gaps between sleep segments shorter than this aren't counted as a wake.
    static let minimumWakeGap: TimeInterval = 120

    private struct Interval { var start: Date; var end: Date }

    static func summarize(_ samples: [HKCategorySample]) -> [NightSleepSummary] {
        let groups = Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }
        return groups
            .compactMap { summarizeOne(sourceID: $0.key, samples: $0.value) }
            .sorted { $0.asleepMinutes > $1.asleepMinutes }
    }

    /// The preferred source by (partial, case-insensitive) name, else the one
    /// that recorded the most sleep.
    static func pick(from summaries: [NightSleepSummary], preferred: String) -> NightSleepSummary? {
        let want = preferred.trimmingCharacters(in: .whitespaces)
        if !want.isEmpty,
           let match = summaries.first(where: { $0.sourceName.localizedCaseInsensitiveContains(want) }) {
            return match
        }
        return summaries.first
    }

    private static func summarizeOne(sourceID: String, samples: [HKCategorySample]) -> NightSleepSummary? {
        let core = HKCategoryValueSleepAnalysis.asleepCore.rawValue
        let deep = HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        let rem = HKCategoryValueSleepAnalysis.asleepREM.rawValue
        let unspecified = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        let inBed = HKCategoryValueSleepAnalysis.inBed.rawValue
        let asleepValues: Set<Int> = [core, deep, rem, unspecified]

        let asleep = samples.filter { asleepValues.contains($0.value) }
        guard !asleep.isEmpty else { return nil }

        // Merge overlapping or touching segments.
        let sorted = asleep.map { Interval(start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
        var merged: [Interval] = []
        for iv in sorted {
            if let last = merged.last, iv.start <= last.end.addingTimeInterval(1) {
                merged[merged.count - 1].end = max(last.end, iv.end)
            } else {
                merged.append(iv)
            }
        }

        let asleepSeconds = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        var wakes = 0
        var awakeSeconds: TimeInterval = 0
        if merged.count > 1 {
            for i in 1..<merged.count {
                let gap = merged[i].start.timeIntervalSince(merged[i - 1].end)
                if gap >= minimumWakeGap {
                    wakes += 1
                    awakeSeconds += gap
                }
            }
        }

        func minutes(_ value: Int) -> Double {
            samples.filter { $0.value == value }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
        }

        let bed = samples.filter { $0.value == inBed }
        return NightSleepSummary(
            sourceID: sourceID,
            sourceName: samples.first?.sourceRevision.source.name ?? sourceID,
            inBedStart: bed.map(\.startDate).min(),
            inBedEnd: bed.map(\.endDate).max(),
            sleepOnset: merged.first?.start,
            finalWake: merged.last?.end,
            asleepMinutes: asleepSeconds / 60,
            awakenings: wakes,
            awakeMinutes: awakeSeconds / 60,
            coreMinutes: minutes(core),
            deepMinutes: minutes(deep),
            remMinutes: minutes(rem)
        )
    }
}
