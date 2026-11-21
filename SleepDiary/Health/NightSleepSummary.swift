import Foundation
import HealthKit

enum SleepStage: Hashable {
    case awake, rem, core, deep, unspecified
}

/// A stretch of one stage, or an awake gap between sleep segments.
struct SleepSegment: Hashable {
    let start: Date
    let end: Date
    let stage: SleepStage
}

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
    /// Asleep segments by stage plus every awake gap between them, in time order.
    let segments: [SleepSegment]
    /// Gaps of at least `minimumWakeGap` between asleep segments.
    let wakes: [DateInterval]
    /// Gaps shorter than `minimumWakeGap`.
    let briefStirrings: Int

    var id: String { sourceID }

    /// From getting into bed (or falling asleep, if earlier or unknown) to the final wake.
    var inBedSpanStart: Date? {
        guard let onset = sleepOnset else { return inBedStart }
        guard let bed = inBedStart else { return onset }
        return min(bed, onset)
    }

    var inBedSpanMinutes: Double? {
        guard let a = inBedSpanStart, let b = finalWake, b > a else { return nil }
        return b.timeIntervalSince(a) / 60
    }

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
            .compactMap { group in
                summarizeOne(
                    sourceID: group.key,
                    sourceName: group.value.first?.sourceRevision.source.name ?? group.key,
                    samples: group.value.map { RawSample(start: $0.startDate, end: $0.endDate, value: $0.value) }
                )
            }
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

    /// A sleep analysis sample reduced to what the summary needs.
    struct RawSample {
        let start: Date
        let end: Date
        let value: Int
    }

    static func summarizeOne(sourceID: String, sourceName: String, samples: [RawSample]) -> NightSleepSummary? {
        let core = HKCategoryValueSleepAnalysis.asleepCore.rawValue
        let deep = HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        let rem = HKCategoryValueSleepAnalysis.asleepREM.rawValue
        let unspecified = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        let inBed = HKCategoryValueSleepAnalysis.inBed.rawValue
        let asleepValues: Set<Int> = [core, deep, rem, unspecified]

        let asleep = samples.filter { asleepValues.contains($0.value) }
        guard !asleep.isEmpty else { return nil }

        // Merge overlapping or touching segments.
        let sorted = asleep.map { Interval(start: $0.start, end: $0.end) }
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
        var wakes: [DateInterval] = []
        var stirrings = 0
        var gaps: [SleepSegment] = []
        if merged.count > 1 {
            for i in 1..<merged.count {
                let start = merged[i - 1].end
                let end = merged[i].start
                let gap = end.timeIntervalSince(start)
                gaps.append(SleepSegment(start: start, end: end, stage: .awake))
                if gap >= minimumWakeGap {
                    wakes.append(DateInterval(start: start, end: end))
                } else {
                    stirrings += 1
                }
            }
        }
        let awakeSeconds = wakes.reduce(0.0) { $0 + $1.duration }

        func stage(_ value: Int) -> SleepStage {
            switch value {
            case rem: return .rem
            case core: return .core
            case deep: return .deep
            default: return .unspecified
            }
        }
        let stageSegments = asleep.map { SleepSegment(start: $0.start, end: $0.end, stage: stage($0.value)) }
        let segments = (stageSegments + gaps).sorted { $0.start < $1.start }

        func minutes(_ value: Int) -> Double {
            samples.filter { $0.value == value }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
        }

        let bed = samples.filter { $0.value == inBed }
        return NightSleepSummary(
            sourceID: sourceID,
            sourceName: sourceName,
            inBedStart: bed.map(\.start).min(),
            inBedEnd: bed.map(\.end).max(),
            sleepOnset: merged.first?.start,
            finalWake: merged.last?.end,
            asleepMinutes: asleepSeconds / 60,
            awakenings: wakes.count,
            awakeMinutes: awakeSeconds / 60,
            coreMinutes: minutes(core),
            deepMinutes: minutes(deep),
            remMinutes: minutes(rem),
            segments: segments,
            wakes: wakes,
            briefStirrings: stirrings
        )
    }
}
