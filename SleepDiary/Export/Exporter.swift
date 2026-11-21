import Foundation
import UIKit

struct ExportRow {
    let draft: EntryDraft
    let health: NightSleepSummary?
}

enum Exporter {
    static let columns: [String] = [
        "Night",
        "Medication", "Med time",
        "Bed", "Fell asleep", "To fall asleep", "Wakes", "Awake", "Final wake", "Total sleep",
        "Health source", "H: in bed", "H: asleep", "H: wakes", "H: awake", "H: final wake", "H: total sleep",
        "Caffeine", "Alcohol", "Naps",
        "Rested (1-5)", "Grogginess", "Daytime sleepiness", "Dizziness", "Other effects", "Notes",
    ]

    static func values(_ r: ExportRow) -> [String] {
        let d = r.draft
        let h = r.health
        var caffeine = ""
        if !d.caffeine.isEmpty {
            let items = d.caffeine.map { "\(Fmt.time($0.time)) \($0.label) \(Int($0.mg))mg" }
            caffeine = items.joined(separator: "; ") + " (total \(Int(d.totalCaffeineMg))mg)"
        }
        let alcohol = d.alcohol.map { "\(Fmt.time($0.time)) x\(Fmt.number($0.drinks))" }.joined(separator: "; ")
        let naps = d.naps.map { "\(Fmt.time($0.start)) \(Fmt.hm(Double($0.minutes)))" }.joined(separator: "; ")

        var medication = "None"
        var medTime = ""
        if d.tookMedication {
            medication = "\(d.medicationName) \(d.medicationDose)".trimmingCharacters(in: .whitespaces)
            medTime = Fmt.time(d.medicationTime)
        }

        var healthCells: [String] = Array(repeating: "", count: 7)
        if let h {
            healthCells = [
                h.sourceName,
                Fmt.time(h.inBedStart),
                Fmt.time(h.sleepOnset),
                String(h.awakenings),
                Fmt.hm(h.awakeMinutes),
                Fmt.time(h.finalWake),
                Fmt.hm(h.asleepMinutes),
            ]
        }

        var out: [String] = [Fmt.night(d.night), medication, medTime]
        out += [Fmt.time(d.bedTime), Fmt.time(d.sleepOnset), Fmt.hm(d.latencyMinutes)]
        out += [String(d.awakenings), Fmt.hm(Double(d.minutesAwake))]
        out += [Fmt.time(d.finalWake), Fmt.hm(d.totalSleepMinutes)]
        out += healthCells
        out += [caffeine, alcohol, naps]
        out += [String(d.rested), d.grogginess.label, d.daytimeSleepiness.label, d.dizziness.label]
        out += [d.otherEffects, d.notes]
        return out
    }

    // MARK: CSV

    static func csv(_ rows: [ExportRow]) -> String {
        func cell(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = [columns.map(cell).joined(separator: ",")]
        for r in rows { lines.append(values(r).map(cell).joined(separator: ",")) }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: Summary

    struct Averages {
        var nights = 0
        var medNights = 0
        var diarySleep: Double?
        var diaryLatency: Double?
        var diaryWakes: Double?
        var healthSleep: Double?
        var healthWakes: Double?
        var medToSleep: Double?
        var rested: Double?
        var caffeineNights = 0
        var alcoholNights = 0
    }

    static func averages(_ rows: [ExportRow]) -> Averages {
        func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        let ds = rows.map(\.draft)
        let hs = rows.compactMap(\.health)
        var a = Averages()
        a.nights = rows.count
        a.medNights = ds.filter(\.tookMedication).count
        a.diarySleep = mean(ds.map(\.totalSleepMinutes))
        a.diaryLatency = mean(ds.map(\.latencyMinutes))
        a.diaryWakes = mean(ds.map { Double($0.awakenings) })
        a.healthSleep = mean(hs.map(\.asleepMinutes))
        a.healthWakes = mean(hs.map { Double($0.awakenings) })
        a.medToSleep = mean(ds.compactMap(\.medToSleepMinutes))
        a.rested = mean(ds.map { Double($0.rested) })
        a.caffeineNights = ds.filter { !$0.caffeine.isEmpty }.count
        a.alcoholNights = ds.filter { !$0.alcohol.isEmpty }.count
        return a
    }

    // MARK: HTML / PDF

    static func html(_ rows: [ExportRow]) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let a = averages(rows)
        let first = rows.first.map { Fmt.night($0.draft.night) } ?? ""
        let last = rows.last.map { Fmt.night($0.draft.night) } ?? ""
        let restedText = a.rested.map { String(format: "%.1f", $0) } ?? "–"
        let wakesText = a.diaryWakes.map { String(format: "%.1f", $0) } ?? "–"
        let hWakesText = a.healthWakes.map { String(format: "%.1f", $0) } ?? "–"

        var html = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 7.5pt; color: #111; }
        h1 { font-size: 13pt; margin: 0 0 4px 0; }
        .sub { color: #555; margin-bottom: 8px; }
        .summary { margin-bottom: 10px; font-size: 8.5pt; }
        .summary td { padding: 1px 12px 1px 0; }
        table.log { border-collapse: collapse; width: 100%; }
        table.log th, table.log td { border: 0.5px solid #999; padding: 2px 3px; vertical-align: top; }
        table.log th { background: #eee; font-weight: 600; }
        th.h, td.h { background: #f3f7ff; }
        </style></head><body>
        <h1>Sleep diary</h1>
        <div class="sub">\(esc(first)) to \(esc(last)), \(a.nights) nights. Diary columns are my own estimates; columns marked H: come from Apple Health.</div>
        <table class="summary">
        <tr><td>Average sleep (diary)</td><td><b>\(Fmt.hm(a.diarySleep))</b></td>
            <td>Average sleep (Health)</td><td><b>\(Fmt.hm(a.healthSleep))</b></td></tr>
        <tr><td>Average time to fall asleep</td><td><b>\(Fmt.hm(a.diaryLatency))</b></td>
            <td>Medication to sleep (average)</td><td><b>\(Fmt.hm(a.medToSleep))</b></td></tr>
        <tr><td>Average wakes (diary / Health)</td><td><b>\(wakesText) / \(hWakesText)</b></td>
            <td>Average rested score</td><td><b>\(restedText) of 5</b></td></tr>
        <tr><td>Nights with medication</td><td><b>\(a.medNights)</b></td>
            <td>Nights with caffeine / alcohol</td><td><b>\(a.caffeineNights) / \(a.alcoholNights)</b></td></tr>
        </table>
        <table class="log"><tr>
        """
        for c in columns {
            let cls = c.hasPrefix("H:") || c == "Health source" ? " class=\"h\"" : ""
            html += "<th\(cls)>\(esc(c))</th>"
        }
        html += "</tr>"
        for r in rows {
            html += "<tr>"
            for (c, v) in zip(columns, values(r)) {
                let cls = c.hasPrefix("H:") || c == "Health source" ? " class=\"h\"" : ""
                html += "<td\(cls)>\(esc(v))</td>"
            }
            html += "</tr>"
        }
        html += "</table></body></html>"
        return html
    }

    /// Renders HTML to a landscape US Letter PDF.
    @MainActor
    static func pdf(html: String) -> Data {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let paper = CGRect(x: 0, y: 0, width: 792, height: 612)
        let printable = paper.insetBy(dx: 28, dy: 28)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    @MainActor
    static func write(rows: [ExportRow]) throws -> [URL] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let stamp = df.string(from: Date())
        let dir = FileManager.default.temporaryDirectory

        let csvURL = dir.appendingPathComponent("sleep-diary-\(stamp).csv")
        try Data(csv(rows).utf8).write(to: csvURL, options: .atomic)

        let pdfURL = dir.appendingPathComponent("sleep-diary-\(stamp).pdf")
        try pdf(html: html(rows)).write(to: pdfURL, options: .atomic)

        return [pdfURL, csvURL]
    }
}
