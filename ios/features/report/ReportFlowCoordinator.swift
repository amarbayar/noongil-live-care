import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Manages the voice-driven report generation flow.
/// States: idle → awaitingPeriod → generating → presenting
@MainActor
final class ReportFlowCoordinator: ObservableObject {

    enum FlowState: Equatable {
        case idle
        case awaitingPeriod
        case generating
        case presenting
    }

    enum ReportAction {
        case share
        case readMore
        case dismiss
    }

    // MARK: - Published State

    @Published var flowState: FlowState = .idle
    @Published var generatedPDFData: Data?
    @Published var verbalSummary: String?

    var isActive: Bool { flowState != .idle }

    // MARK: - Dependencies

    private let featureFlags: FeatureFlagService?

    init(featureFlags: FeatureFlagService? = nil) {
        self.featureFlags = featureFlags
    }

    // MARK: - Trigger Detection

    /// Returns true if the transcript contains a report trigger keyword.
    func detectReportTrigger(_ transcript: String) -> Bool {
        if let flags = featureFlags, !flags.doctorReportEnabled { return false }

        let lower = transcript.lowercased()
        return Config.reportKeywords.contains { lower.contains($0) }
    }

    // MARK: - Flow Control

    /// Begins the report flow. Returns Mira's prompt asking for the time period.
    func beginReportFlow() -> String {
        flowState = .awaitingPeriod
        return "Sure! What time period would you like the report to cover? For example, you can say \"last two weeks\" or \"past month\"."
    }

    /// Processes the user's period selection. Returns Mira's response or nil if unrecognized.
    func handlePeriodSelection(_ transcript: String) -> (days: Int, response: String)? {
        let lower = transcript.lowercased()

        // Try to match a period keyword
        for (keyword, days) in Config.reportPeriodKeywords.sorted(by: { $0.key.count > $1.key.count }) {
            if lower.contains(keyword) {
                flowState = .generating
                return (days, "Got it, I'll prepare your health summary for the past \(days) days. Give me a moment.")
            }
        }

        // Try to extract a number of days/weeks
        if let match = extractNumericPeriod(from: lower) {
            flowState = .generating
            return (match, "Got it, I'll prepare your health summary for the past \(match) days. Give me a moment.")
        }

        // Fallback: default to 14 days
        flowState = .generating
        return (14, "I'll prepare your summary for the past two weeks. Give me a moment.")
    }

    /// Generates the report and returns the verbal summary.
    func generateReport(
        days: Int,
        checkIns: [CheckIn],
        medications: [Medication],
        userName: String?
    ) -> String {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate

        let reportData = ReportService.generateReportData(
            checkIns: checkIns,
            medications: medications,
            from: startDate,
            to: endDate,
            userName: userName
        )

        #if canImport(UIKit)
        generatedPDFData = ReportService.renderPDF(from: reportData, userName: userName)
        #endif

        verbalSummary = reportData.verbalSummary
        flowState = .presenting

        return reportData.verbalSummary + " Would you like me to share the full report, read more details, or are we done?"
    }

    /// Processes the user's response after hearing the summary.
    func handlePresentationResponse(_ transcript: String) -> (response: String, action: ReportAction)? {
        let lower = transcript.lowercased()

        if lower.contains("share") || lower.contains("send") || lower.contains("export") {
            return ("Opening the share sheet now.", .share)
        }

        if lower.contains("read more") || lower.contains("more detail") || lower.contains("tell me more") {
            if let summary = verbalSummary {
                return (summary, .readMore)
            }
            return ("I don't have additional details right now.", .readMore)
        }

        if lower.contains("done") || lower.contains("no") || lower.contains("that's it")
            || lower.contains("dismiss") || lower.contains("thanks") || lower.contains("thank you") {
            reset()
            return ("Great, your report is ready whenever you need it.", .dismiss)
        }

        return nil
    }

    /// Resets the coordinator to idle state.
    func reset() {
        flowState = .idle
        generatedPDFData = nil
        verbalSummary = nil
    }

    // MARK: - Helpers

    private func extractNumericPeriod(from text: String) -> Int? {
        let numberWords: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10
        ]

        // "X days"
        if text.contains("day") {
            for (word, num) in numberWords {
                if text.contains(word) { return num }
            }
            if let num = extractDigits(from: text) { return num }
        }

        // "X weeks"
        if text.contains("week") {
            for (word, num) in numberWords {
                if text.contains(word) { return num * 7 }
            }
            if let num = extractDigits(from: text) { return num * 7 }
        }

        // "X months"
        if text.contains("month") {
            for (word, num) in numberWords {
                if text.contains(word) { return num * 30 }
            }
            if let num = extractDigits(from: text) { return num * 30 }
        }

        return nil
    }

    private func extractDigits(from text: String) -> Int? {
        let pattern = try? NSRegularExpression(pattern: "\\b(\\d+)\\b")
        let range = NSRange(text.startIndex..., in: text)
        if let match = pattern?.firstMatch(in: text, range: range),
           let numRange = Range(match.range(at: 1), in: text) {
            return Int(text[numRange])
        }
        return nil
    }
}
