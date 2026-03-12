import SwiftUI

/// Date range picker + report generation + PDF sharing for doctor visits.
/// Voice-first companion — the verbal summary can be read aloud by Mira.
struct ReportView: View {
    @EnvironmentObject var theme: ThemeService
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var authService: AuthService

    @State private var startDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var reportData: ReportService.ReportData?
    @State private var isLoading = false
    @State private var showShareSheet = false
    @State private var pdfURL: URL?

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    dateRangeSection
                    generateButton

                    if isLoading {
                        ProgressView()
                            .tint(theme.primary)
                            .padding()
                    }

                    if let report = reportData {
                        summarySection(report)
                        overviewSection(report)
                        if !report.symptomSummaries.isEmpty {
                            symptomSection(report)
                        }
                        if !report.notableEvents.isEmpty {
                            eventsSection(report)
                        }
                        shareButton
                    }
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.headline)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                }

                VStack(alignment: .leading) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Generate

    private var generateButton: some View {
        Button {
            Task { await generateReport() }
        } label: {
            HStack {
                Image(systemName: "doc.text")
                Text("Generate Summary")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(theme.primary)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
        .disabled(isLoading)
        .accessibilityLabel("Generate health summary")
    }

    // MARK: - Verbal Summary

    private func summarySection(_ report: ReportService.ReportData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)

            Text(report.verbalSummary)
                .font(.body)
                .foregroundStyle(theme.textSecondary)
        }
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Overview

    private func overviewSection(_ report: ReportService.ReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)

            overviewRow("Check-ins", value: "\(report.checkInCount)")
            overviewRow("Mood", value: report.moodAverage.map { "\(String(format: "%.1f", $0))/5 (\(report.moodTrend))" } ?? "No data")
            overviewRow("Sleep", value: report.sleepAverage.map { "\(String(format: "%.1f", $0)) hrs (\(report.sleepTrend))" } ?? "No data")
            overviewRow("Adherence", value: report.medicationAdherencePercent.map { "\(Int($0.rounded()))%" } ?? "No data")
        }
        .glassCard(cornerRadius: 12)
    }

    private func overviewRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(theme.text)
        }
    }

    // MARK: - Symptoms

    private func symptomSection(_ report: ReportService.ReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observed Patterns")
                .font(.headline)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)

            ForEach(report.symptomSummaries, id: \.type) { symptom in
                HStack {
                    Text(ReportService.symptomDisplayName(symptom.type))
                        .font(.subheadline)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text("\(symptom.occurrences)x")
                        .font(.subheadline.bold())
                        .foregroundStyle(theme.textSecondary)
                    Text("(\(symptom.trend))")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Notable Events

    private func eventsSection(_ report: ReportService.ReportData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notable Events")
                .font(.headline)
                .foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(report.notableEvents.prefix(10).enumerated()), id: \.offset) { _, event in
                Text("• \(event)")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Share

    private var shareButton: some View {
        Button {
            sharePDF()
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Share PDF")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(theme.primary.opacity(0.15))
            .foregroundStyle(theme.primary)
            .cornerRadius(12)
        }
        .accessibilityLabel("Share health summary as PDF")
    }

    // MARK: - Actions

    private func generateReport() async {
        isLoading = true
        defer { isLoading = false }

        guard let uid = authService.currentUser?.uid else { return }

        do {
            let checkIns: [CheckIn] = try await storageService.fetchAll(
                CheckIn.self,
                from: "checkins",
                userId: uid,
                limit: 500
            )
            let medications: [Medication] = try await storageService.fetchAll(
                Medication.self,
                from: "medications",
                userId: uid,
                limit: 100
            )

            let userName = authService.currentUser?.displayName

            reportData = ReportService.generateReportData(
                checkIns: checkIns,
                medications: medications,
                from: startDate,
                to: endDate,
                userName: userName
            )
        } catch {
            print("[ReportView] Error loading data: \(error)")
        }
    }

    private func sharePDF() {
        #if canImport(UIKit)
        guard let report = reportData else { return }
        let userName = authService.currentUser?.displayName
        let data = ReportService.renderPDF(from: report, userName: userName)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("Noongil-Health-Summary.pdf")
        try? data.write(to: fileURL)

        pdfURL = fileURL
        showShareSheet = true
        #endif
    }
}

// MARK: - Share Sheet

#if canImport(UIKit)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
