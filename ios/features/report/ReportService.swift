import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Generates health summary reports from check-in data.
/// Pure computation for the data layer; PDF rendering uses UIKit/PDFKit.
struct ReportService {

    // MARK: - Report Data

    struct DailyDataPoint {
        let date: Date
        let value: Double
    }

    struct PerMedicationAdherence {
        let name: String
        let takenCount: Int
        let totalCount: Int
        var percent: Double { totalCount > 0 ? Double(takenCount) / Double(totalCount) * 100 : 0 }
    }

    struct CorrelationEntry {
        let description: String
        let coefficient: Double
        let pValue: Double?
    }

    struct ReportConcern {
        let theme: String
        let occurrenceCount: Int
        let quotes: [String]
    }

    struct ReportData {
        let dateRange: ClosedRange<Date>
        let checkInCount: Int
        let moodAverage: Double?
        let moodTrend: String           // "improving", "stable", "declining"
        let sleepAverage: Double?
        let sleepTrend: String
        let medicationAdherencePercent: Double?
        let symptomSummaries: [SymptomReportEntry]
        let notableEvents: [String]
        let verbalSummary: String

        // Extended fields for 8-section PDF
        var executiveSummary: String?
        var moodTimeSeries: [DailyDataPoint]
        var sleepTimeSeries: [DailyDataPoint]
        var symptomTimeSeries: [SymptomType: [DailyDataPoint]]
        var perMedicationAdherence: [PerMedicationAdherence]
        var correlations: [CorrelationEntry]
        var concerns: [ReportConcern]
    }

    struct SymptomReportEntry {
        let type: SymptomType
        let occurrences: Int
        let averageSeverity: Double?
        let trend: String               // "improving", "stable", "worsening"
    }

    // MARK: - Generate Report Data

    /// Computes report data from check-ins within the given date range.
    static func generateReportData(
        checkIns: [CheckIn],
        medications: [Medication],
        from startDate: Date,
        to endDate: Date,
        userName: String?
    ) -> ReportData {
        let range = startDate...endDate
        let filtered = checkIns.filter { range.contains($0.startedAt) }
            .sorted { $0.startedAt < $1.startedAt }

        let moodAvg = HealthHistoryService.averageMood(from: filtered)
        let sleepAvg = HealthHistoryService.averageSleep(from: filtered)
        let symptoms = buildSymptomReport(from: filtered)
        let adherence = calculateAdherence(from: filtered, medications: medications)
        let moodTrend = calculateTrend(filtered.compactMap { $0.mood?.score })
        let sleepTrend = calculateTrend(filtered.compactMap { $0.sleep?.hours }.map { Int($0) })
        let events = extractNotableEvents(from: filtered)
        let verbal = buildVerbalSummary(
            checkInCount: filtered.count,
            dayCount: daysBetween(startDate, endDate),
            moodAvg: moodAvg,
            moodTrend: moodTrend,
            sleepAvg: sleepAvg,
            adherencePercent: adherence,
            symptoms: symptoms,
            userName: userName
        )

        let moodTs = HealthHistoryService.moodTrend(from: filtered).map {
            DailyDataPoint(date: $0.date, value: Double($0.score))
        }
        let sleepTs = HealthHistoryService.sleepTrend(from: filtered).map {
            DailyDataPoint(date: $0.date, value: $0.hours)
        }
        let symptomTs = buildSymptomTimeSeries(from: filtered)
        let perMedAdherence = buildPerMedicationAdherence(from: filtered)

        return ReportData(
            dateRange: range,
            checkInCount: filtered.count,
            moodAverage: moodAvg,
            moodTrend: moodTrend,
            sleepAverage: sleepAvg,
            sleepTrend: sleepTrend,
            medicationAdherencePercent: adherence,
            symptomSummaries: symptoms,
            notableEvents: events,
            verbalSummary: verbal,
            executiveSummary: nil,
            moodTimeSeries: moodTs,
            sleepTimeSeries: sleepTs,
            symptomTimeSeries: symptomTs,
            perMedicationAdherence: perMedAdherence,
            correlations: [],
            concerns: []
        )
    }

    // MARK: - Verbal Summary (H-01)

    /// Builds a natural-language summary suitable for voice delivery.
    static func buildVerbalSummary(
        checkInCount: Int,
        dayCount: Int,
        moodAvg: Double?,
        moodTrend: String,
        sleepAvg: Double?,
        adherencePercent: Double?,
        symptoms: [SymptomReportEntry],
        userName: String?
    ) -> String {
        var parts: [String] = []

        // Opening
        let name = userName ?? "you"
        parts.append("Here's a summary of \(name)'s health over the past \(dayCount) days based on \(checkInCount) check-ins.")

        // Mood
        if let avg = moodAvg {
            let moodDesc = moodDescription(avg)
            parts.append("Overall mood has been \(moodDesc) and \(moodTrend).")
        }

        // Sleep
        if let avg = sleepAvg {
            let rounded = String(format: "%.1f", avg)
            parts.append("Sleep averaged \(rounded) hours per night.")
        }

        // Medication adherence
        if let adherence = adherencePercent {
            let pct = Int(adherence.rounded())
            parts.append("Medication adherence was \(pct) percent.")
        }

        // Top symptoms
        let topSymptoms = symptoms.prefix(3)
        if !topSymptoms.isEmpty {
            let symptomDescs = topSymptoms.map { s in
                let sev = s.averageSeverity.map { severityWord($0) } ?? "mild"
                return "\(symptomDisplayName(s.type)) was mostly \(sev)"
            }
            parts.append(symptomDescs.joined(separator: ". ") + ".")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - PDF Generation

    #if canImport(UIKit)

    private static let pageWidth: CGFloat = 612   // US Letter
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 50
    private static var contentWidth: CGFloat { pageWidth - 2 * margin }

    /// Renders an 8-section professional PDF from report data. Returns PDF as Data.
    static func renderPDF(from report: ReportData, userName: String?) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        return renderer.pdfData { ctx in
            var pageNum = 1
            ctx.beginPage()
            var y: CGFloat = margin

            // Title
            y = drawTitle(report: report, userName: userName, y: y)
            y = drawDivider(context: ctx.cgContext, y: y)

            // Section 1: Executive Summary
            y = checkPageBreak(ctx: ctx, y: y, needed: 80, pageNum: &pageNum)
            y = drawSection(title: "1. Executive Summary", y: y)
            let summary = report.executiveSummary ?? report.verbalSummary
            y = drawBodyText(summary, y: y)
            y += 12

            // Section 2: Symptom Trends
            y = checkPageBreak(ctx: ctx, y: y, needed: 120, pageNum: &pageNum)
            y = drawDivider(context: ctx.cgContext, y: y)
            y = drawSection(title: "2. Symptom Trends", y: y)
            if report.symptomTimeSeries.isEmpty && report.symptomSummaries.isEmpty {
                y = drawBodyText("No symptom data recorded in this period.", y: y)
            } else {
                // Chart per symptom type
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM/dd"
                for (type, points) in report.symptomTimeSeries.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                    y = checkPageBreak(ctx: ctx, y: y, needed: 100, pageNum: &pageNum)
                    let chartPoints = points.map {
                        PDFChartRenderer.DataPoint(label: dateFormatter.string(from: $0.date), value: $0.value)
                    }
                    let chartRect = CGRect(x: margin, y: y, width: contentWidth, height: 80)
                    y = drawBodyText(symptomDisplayName(type), y: y)
                    PDFChartRenderer.drawLineChart(
                        context: ctx.cgContext,
                        dataPoints: chartPoints,
                        rect: chartRect,
                        lineColor: .systemOrange,
                        yAxisLabel: "Severity",
                        yMin: 0, yMax: 5
                    )
                    y = chartRect.maxY + 12
                }
                // Text summaries
                for symptom in report.symptomSummaries {
                    let sevText = symptom.averageSeverity.map { String(format: "%.1f", $0) } ?? "—"
                    y = drawBullet("• \(symptomDisplayName(symptom.type)): \(symptom.occurrences) occurrences, avg severity \(sevText)/5 (\(symptom.trend))", y: y)
                }
            }
            y += 8

            // Section 3: Medication Adherence
            y = checkPageBreak(ctx: ctx, y: y, needed: 100, pageNum: &pageNum)
            y = drawDivider(context: ctx.cgContext, y: y)
            y = drawSection(title: "3. Medication Adherence", y: y)
            if let adherence = report.medicationAdherencePercent {
                y = drawBodyText("Overall adherence: \(Int(adherence.rounded()))%", y: y)
            } else {
                y = drawBodyText("No medication data recorded.", y: y)
            }
            if !report.perMedicationAdherence.isEmpty {
                y += 4
                y = checkPageBreak(ctx: ctx, y: y, needed: CGFloat(report.perMedicationAdherence.count * 22 + 10), pageNum: &pageNum)
                let items = report.perMedicationAdherence.map {
                    PDFChartRenderer.BarItem(
                        label: "\($0.name) (\($0.takenCount)/\($0.totalCount))",
                        value: $0.totalCount > 0 ? Double($0.takenCount) / Double($0.totalCount) : 0
                    )
                }
                let barRect = CGRect(x: margin, y: y, width: contentWidth, height: CGFloat(items.count) * 22)
                y = PDFChartRenderer.drawHorizontalBarChart(
                    context: ctx.cgContext,
                    items: items,
                    rect: barRect,
                    barColor: .systemGreen
                )
            }
            y += 8

            // Section 4: Mood Trajectory
            y = checkPageBreak(ctx: ctx, y: y, needed: 120, pageNum: &pageNum)
            y = drawDivider(context: ctx.cgContext, y: y)
            y = drawSection(title: "4. Mood Trajectory", y: y)
            if report.moodTimeSeries.isEmpty {
                y = drawBodyText("No mood data recorded.", y: y)
            } else {
                if let avg = report.moodAverage {
                    y = drawBodyText("Average mood: \(String(format: "%.1f", avg))/5 (\(report.moodTrend))", y: y)
                }
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM/dd"
                let chartPoints = report.moodTimeSeries.map {
                    PDFChartRenderer.DataPoint(label: dateFormatter.string(from: $0.date), value: $0.value)
                }
                let chartRect = CGRect(x: margin, y: y, width: contentWidth, height: 90)
                PDFChartRenderer.drawLineChart(
                    context: ctx.cgContext,
                    dataPoints: chartPoints,
                    rect: chartRect,
                    lineColor: .systemPurple,
                    yAxisLabel: "Mood",
                    yMin: 1, yMax: 5
                )
                y = chartRect.maxY + 8
            }
            y += 8

            // Section 5: Sleep Data
            y = checkPageBreak(ctx: ctx, y: y, needed: 120, pageNum: &pageNum)
            y = drawDivider(context: ctx.cgContext, y: y)
            y = drawSection(title: "5. Sleep Data", y: y)
            if report.sleepTimeSeries.isEmpty {
                y = drawBodyText("No sleep data recorded.", y: y)
            } else {
                if let avg = report.sleepAverage {
                    y = drawBodyText("Average sleep: \(String(format: "%.1f", avg)) hours/night (\(report.sleepTrend))", y: y)
                }
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM/dd"
                let chartPoints = report.sleepTimeSeries.map {
                    PDFChartRenderer.DataPoint(label: dateFormatter.string(from: $0.date), value: $0.value)
                }
                let chartRect = CGRect(x: margin, y: y, width: contentWidth, height: 90)
                PDFChartRenderer.drawBarChart(
                    context: ctx.cgContext,
                    dataPoints: chartPoints,
                    rect: chartRect,
                    barColor: .systemBlue,
                    yAxisLabel: "Hours",
                    yMin: 0, yMax: 12
                )
                y = chartRect.maxY + 8
            }
            y += 8

            // Section 6: Activity & Mobility
            y = checkPageBreak(ctx: ctx, y: y, needed: 60, pageNum: &pageNum)
            y = drawDivider(context: ctx.cgContext, y: y)
            y = drawSection(title: "6. Activity & Mobility", y: y)
            y = drawBodyText("Available in a future update.", y: y)
            y += 8

            // Section 7: Correlations & Insights
            y = checkPageBreak(ctx: ctx, y: y, needed: 60, pageNum: &pageNum)
            y = drawDivider(context: ctx.cgContext, y: y)
            y = drawSection(title: "7. Correlations & Insights", y: y)
            if report.correlations.isEmpty {
                y = drawBodyText("Correlations will appear once sufficient data has been collected.", y: y)
            } else {
                for corr in report.correlations {
                    y = checkPageBreak(ctx: ctx, y: y, needed: 20, pageNum: &pageNum)
                    let pVal = corr.pValue.map { String(format: ", p=%.3f", $0) } ?? ""
                    y = drawBullet("• \(corr.description) (r=\(String(format: "%.2f", corr.coefficient))\(pVal))", y: y)
                }
            }
            y += 8

            // Section 8: Self-Reported Concerns
            y = checkPageBreak(ctx: ctx, y: y, needed: 60, pageNum: &pageNum)
            y = drawDivider(context: ctx.cgContext, y: y)
            y = drawSection(title: "8. Self-Reported Concerns", y: y)
            if report.concerns.isEmpty {
                y = drawBodyText("No recurring concerns identified in this period.", y: y)
            } else {
                for concern in report.concerns {
                    y = checkPageBreak(ctx: ctx, y: y, needed: 40, pageNum: &pageNum)
                    y = drawBullet("• \(concern.theme) (reported \(concern.occurrenceCount) time\(concern.occurrenceCount == 1 ? "" : "s"))", y: y)
                    for quote in concern.quotes.prefix(2) {
                        y = drawBodyText("  \"\(quote)\"", y: y, indent: 24, fontSize: 10, color: .gray)
                    }
                }
            }

            // Footer on last page
            drawPageFooter(ctx: ctx, pageNum: pageNum)
        }
    }

    // MARK: - PDF Drawing Helpers

    private static func drawTitle(report: ReportData, userName: String?, y: CGFloat) -> CGFloat {
        var y = y
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        "Health Summary".draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        y += 32

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.darkGray
        ]
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let lower = dateFormatter.string(from: report.dateRange.lowerBound)
        let upper = dateFormatter.string(from: report.dateRange.upperBound)
        let rangeText = "\(lower) — \(upper)"
        let subtitle = userName != nil ? "\(userName!) • \(rangeText)" : rangeText
        subtitle.draw(at: CGPoint(x: margin, y: y), withAttributes: subtitleAttrs)
        y += 24
        return y
    }

    private static func drawSection(title: String, y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
        return y + 22
    }

    private static func drawBodyText(
        _ text: String,
        y: CGFloat,
        indent: CGFloat = 0,
        fontSize: CGFloat = 11,
        color: UIColor = .darkGray
    ) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: color
        ]
        let maxWidth = contentWidth - indent
        let nsText = text as NSString
        let constraintSize = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let boundingRect = nsText.boundingRect(
            with: constraintSize,
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        nsText.draw(
            in: CGRect(x: margin + indent, y: y, width: maxWidth, height: boundingRect.height),
            withAttributes: attrs
        )
        return y + boundingRect.height + 4
    }

    private static func drawBullet(_ text: String, y: CGFloat) -> CGFloat {
        drawBodyText(text, y: y, indent: 8)
    }

    private static func drawDivider(context: CGContext, y: CGFloat) -> CGFloat {
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        context.strokePath()
        return y + 12
    }

    private static func drawPageFooter(ctx: UIGraphicsPDFRendererContext, pageNum: Int) {
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: UIColor.gray
        ]
        let disclaimer = "Generated by Noongil · Data sourced from self-report via voice check-ins. Not a clinical diagnostic instrument."
        disclaimer.draw(at: CGPoint(x: margin, y: pageHeight - margin + 10), withAttributes: footerAttrs)

        let pageText = "Page \(pageNum)"
        let pageAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.gray
        ]
        let textWidth = (pageText as NSString).size(withAttributes: pageAttrs).width
        pageText.draw(at: CGPoint(x: pageWidth - margin - textWidth, y: pageHeight - margin + 10), withAttributes: pageAttrs)
    }

    /// Starts a new page if the remaining space is insufficient.
    @discardableResult
    private static func checkPageBreak(
        ctx: UIGraphicsPDFRendererContext,
        y: CGFloat,
        needed: CGFloat,
        pageNum: inout Int
    ) -> CGFloat {
        let maxY = pageHeight - margin - 20 // Leave room for footer
        if y + needed > maxY {
            drawPageFooter(ctx: ctx, pageNum: pageNum)
            ctx.beginPage()
            pageNum += 1
            return margin
        }
        return y
    }

    #endif

    // MARK: - Private Helpers

    private static func buildSymptomTimeSeries(from checkIns: [CheckIn]) -> [SymptomType: [DailyDataPoint]] {
        var result: [SymptomType: [DailyDataPoint]] = [:]
        for checkIn in checkIns {
            for symptom in checkIn.symptoms {
                if let severity = symptom.severity {
                    result[symptom.type, default: []].append(
                        DailyDataPoint(date: checkIn.startedAt, value: Double(severity))
                    )
                }
            }
        }
        return result
    }

    private static func buildPerMedicationAdherence(from checkIns: [CheckIn]) -> [PerMedicationAdherence] {
        var taken: [String: Int] = [:]
        var total: [String: Int] = [:]

        for checkIn in checkIns {
            for entry in checkIn.medicationAdherence {
                total[entry.medicationName, default: 0] += 1
                if entry.status == .taken {
                    taken[entry.medicationName, default: 0] += 1
                }
            }
        }

        return total.keys.sorted().map { name in
            PerMedicationAdherence(
                name: name,
                takenCount: taken[name, default: 0],
                totalCount: total[name]!
            )
        }
    }

    private static func buildSymptomReport(from checkIns: [CheckIn]) -> [SymptomReportEntry] {
        let summaries = HealthHistoryService.symptomSummary(from: checkIns)

        return summaries.map { summary in
            // Calculate trend by comparing first half vs second half
            let half = checkIns.count / 2
            let firstHalf = Array(checkIns.prefix(max(half, 1)))
            let secondHalf = Array(checkIns.suffix(max(half, 1)))

            let firstSev = firstHalf.flatMap { $0.symptoms.filter { $0.type == summary.type } }
                .compactMap { $0.severity }
            let secondSev = secondHalf.flatMap { $0.symptoms.filter { $0.type == summary.type } }
                .compactMap { $0.severity }

            let firstAvg = firstSev.isEmpty ? 0.0 : Double(firstSev.reduce(0, +)) / Double(firstSev.count)
            let secondAvg = secondSev.isEmpty ? 0.0 : Double(secondSev.reduce(0, +)) / Double(secondSev.count)

            let trend: String
            if secondAvg < firstAvg - 0.5 {
                trend = "improving"
            } else if secondAvg > firstAvg + 0.5 {
                trend = "worsening"
            } else {
                trend = "stable"
            }

            return SymptomReportEntry(
                type: summary.type,
                occurrences: summary.occurrences,
                averageSeverity: summary.averageSeverity,
                trend: trend
            )
        }
    }

    private static func calculateAdherence(from checkIns: [CheckIn], medications: [Medication]) -> Double? {
        let allAdherence = checkIns.flatMap { $0.medicationAdherence }
        guard !allAdherence.isEmpty else { return nil }

        let taken = allAdherence.filter { $0.status == .taken }.count
        return Double(taken) / Double(allAdherence.count) * 100.0
    }

    static func calculateTrend(_ values: [Int]) -> String {
        guard values.count >= 2 else { return "stable" }
        let half = values.count / 2
        let firstHalf = Array(values.prefix(max(half, 1)))
        let secondHalf = Array(values.suffix(max(half, 1)))

        let firstAvg = Double(firstHalf.reduce(0, +)) / Double(firstHalf.count)
        let secondAvg = Double(secondHalf.reduce(0, +)) / Double(secondHalf.count)

        if secondAvg > firstAvg + 0.3 { return "improving" }
        if secondAvg < firstAvg - 0.3 { return "declining" }
        return "stable"
    }

    private static func calculateAdherencePercent(from checkIns: [CheckIn]) -> Double? {
        calculateAdherence(from: checkIns, medications: [])
    }

    static func extractNotableEvents(from checkIns: [CheckIn]) -> [String] {
        var events: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        for checkIn in checkIns {
            // Low mood
            if let score = checkIn.mood?.score, score <= 2 {
                let dateStr = dateFormatter.string(from: checkIn.startedAt)
                events.append("\(dateStr): Low mood reported (\(score)/5)")
            }

            // High severity symptoms
            for symptom in checkIn.symptoms {
                if let severity = symptom.severity, severity >= 4 {
                    let dateStr = dateFormatter.string(from: checkIn.startedAt)
                    events.append("\(dateStr): \(symptomDisplayName(symptom.type)) severity \(severity)/5")
                }
            }

            // Missed medications
            for med in checkIn.medicationAdherence {
                if med.status == .missed {
                    let dateStr = dateFormatter.string(from: checkIn.startedAt)
                    events.append("\(dateStr): Missed \(med.medicationName)")
                }
            }
        }

        return events
    }

    private static func daysBetween(_ start: Date, _ end: Date) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    private static func moodDescription(_ avg: Double) -> String {
        switch avg {
        case ..<2: return "low"
        case 2..<3: return "mixed"
        case 3..<4: return "moderate"
        default: return "positive"
        }
    }

    private static func severityWord(_ severity: Double) -> String {
        switch severity {
        case ..<2: return "mild"
        case 2..<3: return "moderate"
        case 3..<4: return "moderate to significant"
        default: return "significant"
        }
    }

    static func symptomDisplayName(_ type: SymptomType) -> String {
        switch type {
        case .tremor: return "Tremor"
        case .rigidity: return "Rigidity"
        case .pain: return "Pain"
        case .fatigue: return "Fatigue"
        case .dizziness: return "Dizziness"
        case .nausea: return "Nausea"
        case .headache: return "Headache"
        case .numbness: return "Numbness"
        case .weakness: return "Weakness"
        case .cramping: return "Cramping"
        case .stiffness: return "Stiffness"
        case .balanceIssues: return "Balance issues"
        case .speechDifficulty: return "Speech difficulty"
        case .swallowingDifficulty: return "Swallowing difficulty"
        case .breathingDifficulty: return "Breathing difficulty"
        case .other: return "Other"
        }
    }
}
