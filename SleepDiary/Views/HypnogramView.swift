import SwiftUI

/// Sleep stages across the night in lanes (Awake / REM / Core / Deep), with a
/// numbered pin at each wake-up of 2+ minutes and green markers where sleep
/// started and ended. Sources without stage data get two lanes: Awake / Asleep.
struct HypnogramView: View {
    let summary: NightSleepSummary
    /// Bars only, no labels, pins or axis (for the Home summary).
    var compact = false

    private var laneHeight: CGFloat { compact ? 14 : 26 }
    private var pinArea: CGFloat { compact ? 0 : 26 }
    private var labelWidth: CGFloat { compact ? 0 : 46 }
    private var barHeight: CGFloat { compact ? 6 : 18 }

    private var lanes: [String] {
        summary.hasStages ? ["Awake", "REM", "Core", "Deep"] : ["Awake", "Asleep"]
    }

    private func lane(_ stage: SleepStage) -> Int {
        if !summary.hasStages { return stage == .awake ? 0 : 1 }
        switch stage {
        case .awake: return 0
        case .rem: return 1
        case .core, .unspecified: return 2
        case .deep: return 3
        }
    }

    private var domain: (start: Date, end: Date) {
        let first = summary.inBedSpanStart ?? summary.segments.first?.start ?? Date()
        let last = summary.finalWake ?? summary.segments.last?.end ?? first
        return (first.addingTimeInterval(-10 * 60), max(last, first).addingTimeInterval(15 * 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                if !compact {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lanes, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                            .frame(height: laneHeight)
                    }
                }
                .frame(width: labelWidth, alignment: .leading)
                .padding(.top, pinArea)
                }

                Canvas { context, size in draw(in: &context, size: size) }
                    .frame(height: pinArea + laneHeight * CGFloat(lanes.count))
            }
            if !compact {
                Canvas { context, size in drawAxis(in: &context, size: size) }
                    .frame(height: 16)
                    .padding(.leading, labelWidth)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let n = summary.wakes.count
        return "Sleep stages from \(Fmt.time(summary.sleepOnset)) to \(Fmt.time(summary.finalWake)) with \(n) wake-up\(n == 1 ? "" : "s")"
    }

    private func x(_ date: Date, width: CGFloat) -> CGFloat {
        let d = domain
        let span = d.end.timeIntervalSince(d.start)
        guard span > 0 else { return 0 }
        return CGFloat(date.timeIntervalSince(d.start) / span) * width
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let bottom = size.height

        for i in lanes.indices {
            let y = pinArea + laneHeight * (CGFloat(i) + 0.5)
            context.fill(Path(CGRect(x: 0, y: y, width: w, height: 1)), with: .color(Theme.line))
        }

        for seg in summary.segments {
            let x0 = x(seg.start, width: w)
            let width = max(1.5, x(seg.end, width: w) - x0)
            let y = pinArea + laneHeight * CGFloat(lane(seg.stage)) + (laneHeight - barHeight) / 2
            let rect = CGRect(x: x0, y: y, width: width, height: barHeight)
            context.fill(Path(roundedRect: rect, cornerRadius: min(3, width / 2)),
                         with: .color(Theme.color(for: seg.stage)))
        }

        if compact { return }

        if let onset = summary.sleepOnset {
            marker(&context, at: x(onset, width: w), bottom: bottom, label: "Asleep", leading: true)
        }
        if let end = summary.finalWake {
            marker(&context, at: x(end, width: w), bottom: bottom, label: "Up", leading: false)
        }

        for (i, wake) in summary.wakes.enumerated() {
            let cx = x(wake.start, width: w) + max(1, x(wake.end, width: w) - x(wake.start, width: w)) / 2
            context.fill(Path(CGRect(x: cx - 0.5, y: 20, width: 1, height: 16)), with: .color(Theme.accent))
            context.fill(Path(ellipseIn: CGRect(x: cx - 10, y: 0, width: 20, height: 20)), with: .color(Theme.accent))
            context.draw(Text("\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.onAccent),
                         at: CGPoint(x: cx, y: 10))
        }
    }

    private func marker(_ context: inout GraphicsContext, at mx: CGFloat, bottom: CGFloat, label: String, leading: Bool) {
        context.fill(Path(CGRect(x: mx - 1, y: 4, width: 2, height: bottom - 4)), with: .color(Theme.success))
        let text = Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.success)
        let point = CGPoint(x: leading ? mx + 5 : mx - 5, y: 2)
        context.draw(text, at: point, anchor: leading ? .topLeading : .topTrailing)
    }

    private func drawAxis(in context: inout GraphicsContext, size: CGSize) {
        let cal = Calendar.current
        let d = domain
        let hours = d.end.timeIntervalSince(d.start) / 3600
        let step = hours > 9 ? 2 : 1
        guard var tick = cal.nextDate(after: d.start, matching: DateComponents(minute: 0, second: 0),
                                      matchingPolicy: .nextTime) else { return }
        while tick < d.end {
            let h = cal.component(.hour, from: tick)
            if h % step == 0 {
                let label = "\(h % 12 == 0 ? 12 : h % 12)\(h < 12 ? "a" : "p")"
                context.draw(Text(label).font(.system(size: 11)).foregroundColor(Theme.secondary),
                             at: CGPoint(x: x(tick, width: size.width), y: size.height / 2))
            }
            tick = tick.addingTimeInterval(3600)
        }
    }
}
