import XCTest

final class ReportServiceTests: XCTestCase {

    // MARK: - Report Data Generation

    func testGenerateReportDataWithCheckIns() {
        let checkIns = makeTestCheckIns()
        let startDate = daysAgo(7)
        let endDate = Date()

        let report = ReportService.generateReportData(
            checkIns: checkIns,
            medications: [],
            from: startDate,
            to: endDate,
            userName: "Robert"
        )

        XCTAssertEqual(report.checkInCount, 3)
        XCTAssertNotNil(report.moodAverage)
        XCTAssertNotNil(report.sleepAverage)
    }

    func testGenerateReportDataFiltersDateRange() {
        var old = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(30), moodScore: 3)
        let recent = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(2), moodScore: 4)

        let report = ReportService.generateReportData(
            checkIns: [old, recent],
            medications: [],
            from: daysAgo(7),
            to: Date(),
            userName: nil
        )

        XCTAssertEqual(report.checkInCount, 1, "Should only include check-ins within date range")
    }

    func testEmptyCheckInsProducesEmptyReport() {
        let report = ReportService.generateReportData(
            checkIns: [],
            medications: [],
            from: daysAgo(7),
            to: Date(),
            userName: nil
        )

        XCTAssertEqual(report.checkInCount, 0)
        XCTAssertNil(report.moodAverage)
        XCTAssertNil(report.sleepAverage)
        XCTAssertNil(report.medicationAdherencePercent)
        XCTAssertTrue(report.symptomSummaries.isEmpty)
    }

    // MARK: - Trend Calculation

    func testTrendImprovingWhenScoresIncrease() {
        let trend = ReportService.calculateTrend([2, 2, 3, 4, 4])
        XCTAssertEqual(trend, "improving")
    }

    func testTrendDecliningWhenScoresDecrease() {
        let trend = ReportService.calculateTrend([4, 4, 3, 2, 2])
        XCTAssertEqual(trend, "declining")
    }

    func testTrendStableWhenConsistent() {
        let trend = ReportService.calculateTrend([3, 3, 3, 3])
        XCTAssertEqual(trend, "stable")
    }

    func testTrendStableWithSingleValue() {
        let trend = ReportService.calculateTrend([3])
        XCTAssertEqual(trend, "stable")
    }

    // MARK: - Medication Adherence

    func testAdherenceCalculation() {
        var c1 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1))
        c1.medicationAdherence = [
            MedicationAdherenceEntry(medicationName: "Med A", status: .taken),
            MedicationAdherenceEntry(medicationName: "Med B", status: .taken),
            MedicationAdherenceEntry(medicationName: "Med C", status: .missed)
        ]

        let report = ReportService.generateReportData(
            checkIns: [c1],
            medications: [],
            from: daysAgo(7),
            to: Date(),
            userName: nil
        )

        XCTAssertNotNil(report.medicationAdherencePercent)
        XCTAssertEqual(report.medicationAdherencePercent!, 66.67, accuracy: 0.1)
    }

    // MARK: - Symptom Report

    func testSymptomSummaryInReport() {
        var c1 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(2))
        c1.symptoms = [
            SymptomEntry(type: .tremor, severity: 3),
            SymptomEntry(type: .fatigue, severity: 2)
        ]
        var c2 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1))
        c2.symptoms = [
            SymptomEntry(type: .tremor, severity: 2)
        ]

        let report = ReportService.generateReportData(
            checkIns: [c1, c2],
            medications: [],
            from: daysAgo(7),
            to: Date(),
            userName: nil
        )

        XCTAssertEqual(report.symptomSummaries.count, 2)
        XCTAssertEqual(report.symptomSummaries[0].type, .tremor)
        XCTAssertEqual(report.symptomSummaries[0].occurrences, 2)
    }

    // MARK: - Notable Events

    func testNotableEventsIncludeLowMood() {
        let c1 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1), moodScore: 1)

        let events = ReportService.extractNotableEvents(from: [c1])

        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events[0].contains("Low mood"))
    }

    func testNotableEventsIncludeHighSeveritySymptom() {
        var c1 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1))
        c1.symptoms = [SymptomEntry(type: .tremor, severity: 4)]

        let events = ReportService.extractNotableEvents(from: [c1])

        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events[0].contains("Tremor"))
    }

    func testNotableEventsIncludeMissedMeds() {
        var c1 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1))
        c1.medicationAdherence = [
            MedicationAdherenceEntry(medicationName: "Levodopa", status: .missed)
        ]

        let events = ReportService.extractNotableEvents(from: [c1])

        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events[0].contains("Missed"))
        XCTAssertTrue(events[0].contains("Levodopa"))
    }

    // MARK: - Verbal Summary (H-01)

    func testVerbalSummaryIncludesCheckInCount() {
        let summary = ReportService.buildVerbalSummary(
            checkInCount: 10,
            dayCount: 14,
            moodAvg: 3.5,
            moodTrend: "stable",
            sleepAvg: 7.0,
            adherencePercent: 92.0,
            symptoms: [],
            userName: "Robert"
        )

        XCTAssertTrue(summary.contains("10 check-ins"))
        XCTAssertTrue(summary.contains("14 days"))
        XCTAssertTrue(summary.contains("Robert"))
    }

    func testVerbalSummaryIncludesMood() {
        let summary = ReportService.buildVerbalSummary(
            checkInCount: 5,
            dayCount: 7,
            moodAvg: 4.0,
            moodTrend: "improving",
            sleepAvg: nil,
            adherencePercent: nil,
            symptoms: [],
            userName: nil
        )

        XCTAssertTrue(summary.contains("positive"))
        XCTAssertTrue(summary.contains("improving"))
    }

    func testVerbalSummaryIncludesSleep() {
        let summary = ReportService.buildVerbalSummary(
            checkInCount: 5,
            dayCount: 7,
            moodAvg: nil,
            moodTrend: "stable",
            sleepAvg: 6.5,
            adherencePercent: nil,
            symptoms: [],
            userName: nil
        )

        XCTAssertTrue(summary.contains("6.5"))
        XCTAssertTrue(summary.contains("hours"))
    }

    func testVerbalSummaryIncludesAdherence() {
        let summary = ReportService.buildVerbalSummary(
            checkInCount: 5,
            dayCount: 7,
            moodAvg: nil,
            moodTrend: "stable",
            sleepAvg: nil,
            adherencePercent: 92.0,
            symptoms: [],
            userName: nil
        )

        XCTAssertTrue(summary.contains("92 percent"))
    }

    func testVerbalSummaryIncludesTopSymptoms() {
        let symptoms = [
            ReportService.SymptomReportEntry(type: .tremor, occurrences: 5, averageSeverity: 2.5, trend: "stable")
        ]

        let summary = ReportService.buildVerbalSummary(
            checkInCount: 5,
            dayCount: 7,
            moodAvg: nil,
            moodTrend: "stable",
            sleepAvg: nil,
            adherencePercent: nil,
            symptoms: symptoms,
            userName: nil
        )

        XCTAssertTrue(summary.contains("Tremor"))
    }

    // MARK: - Extended Report Data (Phase 2)

    func testMoodTimeSeriesPopulated() {
        let checkIns = makeTestCheckIns()
        let report = ReportService.generateReportData(
            checkIns: checkIns, medications: [],
            from: daysAgo(7), to: Date(), userName: nil
        )

        XCTAssertEqual(report.moodTimeSeries.count, 3)
        XCTAssertEqual(report.moodTimeSeries[0].value, 3.0)
    }

    func testSleepTimeSeriesPopulated() {
        let checkIns = makeTestCheckIns()
        let report = ReportService.generateReportData(
            checkIns: checkIns, medications: [],
            from: daysAgo(7), to: Date(), userName: nil
        )

        XCTAssertEqual(report.sleepTimeSeries.count, 3)
        XCTAssertEqual(report.sleepTimeSeries[0].value, 7.0)
    }

    func testSymptomTimeSeriesGroupsByType() {
        var c1 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(2))
        c1.symptoms = [
            SymptomEntry(type: .tremor, severity: 3),
            SymptomEntry(type: .fatigue, severity: 2)
        ]
        var c2 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1))
        c2.symptoms = [
            SymptomEntry(type: .tremor, severity: 4)
        ]

        let report = ReportService.generateReportData(
            checkIns: [c1, c2], medications: [],
            from: daysAgo(7), to: Date(), userName: nil
        )

        XCTAssertEqual(report.symptomTimeSeries[.tremor]?.count, 2)
        XCTAssertEqual(report.symptomTimeSeries[.fatigue]?.count, 1)
    }

    func testPerMedicationAdherenceCalculation() {
        var c1 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(2))
        c1.medicationAdherence = [
            MedicationAdherenceEntry(medicationName: "Levodopa", status: .taken),
            MedicationAdherenceEntry(medicationName: "Ropinirole", status: .taken)
        ]
        var c2 = CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1))
        c2.medicationAdherence = [
            MedicationAdherenceEntry(medicationName: "Levodopa", status: .taken),
            MedicationAdherenceEntry(medicationName: "Ropinirole", status: .missed)
        ]

        let report = ReportService.generateReportData(
            checkIns: [c1, c2], medications: [],
            from: daysAgo(7), to: Date(), userName: nil
        )

        XCTAssertEqual(report.perMedicationAdherence.count, 2)

        let levodopa = report.perMedicationAdherence.first { $0.name == "Levodopa" }
        XCTAssertNotNil(levodopa)
        XCTAssertEqual(levodopa?.takenCount, 2)
        XCTAssertEqual(levodopa?.totalCount, 2)
        XCTAssertEqual(levodopa?.percent ?? 0, 100.0, accuracy: 0.01)

        let ropinirole = report.perMedicationAdherence.first { $0.name == "Ropinirole" }
        XCTAssertNotNil(ropinirole)
        XCTAssertEqual(ropinirole?.takenCount, 1)
        XCTAssertEqual(ropinirole?.totalCount, 2)
        XCTAssertEqual(ropinirole?.percent ?? 0, 50.0, accuracy: 0.01)
    }

    // MARK: - PDF Rendering

    #if canImport(UIKit)
    func testRenderPDFReturnsNonEmptyData() {
        let checkIns = makeTestCheckIns()
        let report = ReportService.generateReportData(
            checkIns: checkIns, medications: [],
            from: daysAgo(14), to: Date(), userName: "Robert"
        )

        let pdfData = ReportService.renderPDF(from: report, userName: "Robert")
        XCTAssertFalse(pdfData.isEmpty, "PDF data should not be empty")
        // PDF files start with %PDF
        let header = String(data: pdfData.prefix(5), encoding: .ascii)
        XCTAssertEqual(header, "%PDF-")
    }

    func testRenderPDFHandlesEmptyReport() {
        let report = ReportService.generateReportData(
            checkIns: [], medications: [],
            from: daysAgo(7), to: Date(), userName: nil
        )

        let pdfData = ReportService.renderPDF(from: report, userName: nil)
        XCTAssertFalse(pdfData.isEmpty, "PDF should render even with no data")
    }
    #endif

    // MARK: - Chart Renderer

    #if canImport(UIKit)
    func testLineChartNoCrashEmpty() {
        let points: [PDFChartRenderer.DataPoint] = []
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        renderer.image { ctx in
            PDFChartRenderer.drawLineChart(
                context: ctx.cgContext,
                dataPoints: points,
                rect: rect,
                lineColor: .systemBlue,
                yAxisLabel: "Test"
            )
        }
        // No crash = pass
    }

    func testLineChartSinglePoint() {
        let points = [PDFChartRenderer.DataPoint(label: "Day 1", value: 3.0)]
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        renderer.image { ctx in
            PDFChartRenderer.drawLineChart(
                context: ctx.cgContext,
                dataPoints: points,
                rect: rect,
                lineColor: .systemBlue,
                yAxisLabel: "Test"
            )
        }
        // No crash = pass
    }

    func testBarChartNoCrashEmpty() {
        let points: [PDFChartRenderer.DataPoint] = []
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        renderer.image { ctx in
            PDFChartRenderer.drawBarChart(
                context: ctx.cgContext,
                dataPoints: points,
                rect: rect,
                barColor: .systemGreen,
                yAxisLabel: "Test"
            )
        }
    }

    func testMapDataToPointsScales() {
        let data = [
            PDFChartRenderer.DataPoint(label: "A", value: 0),
            PDFChartRenderer.DataPoint(label: "B", value: 5),
        ]
        let rect = CGRect(x: 10, y: 10, width: 100, height: 50)
        let points = PDFChartRenderer.mapDataToPoints(data: data, rect: rect, yMin: 0, yMax: 5)

        XCTAssertEqual(points.count, 2)
        // First point (value=0) should be at bottom of rect
        XCTAssertEqual(points[0].y, rect.maxY, accuracy: 0.01)
        // Second point (value=5) should be at top of rect
        XCTAssertEqual(points[1].y, rect.minY, accuracy: 0.01)
        // X coordinates should span the rect
        XCTAssertEqual(points[0].x, rect.minX, accuracy: 0.01)
        XCTAssertEqual(points[1].x, rect.maxX, accuracy: 0.01)
    }
    #endif

    // MARK: - Helpers

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    private func makeTestCheckIns() -> [CheckIn] {
        [
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(3), moodScore: 3, sleepHours: 7.0),
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(2), moodScore: 4, sleepHours: 6.5),
            CheckIn.testInstance(userId: "u", type: .morning, startedAt: daysAgo(1), moodScore: 4, sleepHours: 7.5)
        ]
    }
}
