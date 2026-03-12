import SwiftUI
import WebKit

/// Full-screen consent gate shown before the user can access the app.
/// Requires all consent toggles to be enabled before proceeding.
struct PrivacyConsentView: View {
    @EnvironmentObject var consentService: ConsentService
    @EnvironmentObject var theme: ThemeService

    @State private var showingDocument: LegalDocument?

    enum LegalDocument: Identifiable {
        case privacyPolicy
        case termsOfService
        case accessibilityStatement

        var id: String {
            switch self {
            case .privacyPolicy: return "privacy"
            case .termsOfService: return "terms"
            case .accessibilityStatement: return "accessibility"
            }
        }

        var title: String {
            switch self {
            case .privacyPolicy: return "Privacy Policy"
            case .termsOfService: return "Terms of Service"
            case .accessibilityStatement: return "Accessibility"
            }
        }

        var fileName: String {
            switch self {
            case .privacyPolicy: return "privacy-policy"
            case .termsOfService: return "terms-of-service"
            case .accessibilityStatement: return "accessibility-statement"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 48))
                        .foregroundColor(.white)

                    Text("Before We Begin")
                        .font(.title.bold())
                        .foregroundColor(.white)

                    Text("Noongil needs your consent to provide its services. Please review each item below.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 24)

                // Consent Items
                VStack(spacing: 16) {
                    consentToggle(
                        isOn: $consentService.ageConfirmed,
                        title: "I am 18 years or older",
                        description: "You must be at least 18 years old to use Noongil.",
                        icon: "person.badge.shield.checkmark"
                    )

                    consentToggle(
                        isOn: $consentService.healthDataConsent,
                        title: "Health Data Collection",
                        description: "Noongil collects wellness information you share during check-ins, including mood, sleep, and daily experiences. Data is encrypted and stored securely.",
                        icon: "heart.text.clipboard"
                    )

                    consentToggle(
                        isOn: $consentService.aiAnalysisConsent,
                        title: "AI Analysis",
                        description: "Your check-in data is analyzed by AI to identify patterns and provide personalized wellness insights. No data is used to train AI models.",
                        icon: "brain"
                    )

                    consentToggle(
                        isOn: $consentService.voiceProcessingConsent,
                        title: "Voice Processing",
                        description: "In live conversation mode, voice audio is streamed to Google LLC for real-time AI processing. Audio is not stored — only text transcripts are saved. You can use on-device mode instead at any time.",
                        icon: "waveform"
                    )

                    consentToggleWithLink(
                        isOn: $consentService.privacyPolicyAccepted,
                        title: "Privacy Policy",
                        description: "I have read and agree to the Noongil Privacy Policy.",
                        icon: "doc.text",
                        linkText: "Read Privacy Policy",
                        document: .privacyPolicy
                    )

                    consentToggleWithLink(
                        isOn: $consentService.termsAccepted,
                        title: "Terms of Service",
                        description: "I have read and agree to the Noongil Terms of Service.",
                        icon: "doc.plaintext",
                        linkText: "Read Terms of Service",
                        document: .termsOfService
                    )
                }
                .padding(.horizontal)

                // Continue Button
                Button {
                    // All toggles are already bound — nothing extra needed
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(consentService.allConsentsGranted ? theme.primary : .white.opacity(0.2))
                        .foregroundColor(consentService.allConsentsGranted ? .white : .white.opacity(0.4))
                        .cornerRadius(14)
                }
                .disabled(!consentService.allConsentsGranted)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .screenBackground()
        .sheet(item: $showingDocument) { doc in
            LegalDocumentView(document: doc)
                .environmentObject(theme)
        }
    }

    // MARK: - Components

    private func consentToggle(
        isOn: Binding<Bool>,
        title: String,
        description: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(theme.primary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(theme.text)
                }

                Spacer()

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(theme.primary)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .padding(.leading, 44)
        }
        .glassCard()
    }

    private func consentToggleWithLink(
        isOn: Binding<Bool>,
        title: String,
        description: String,
        icon: String,
        linkText: String,
        document: LegalDocument
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(theme.primary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(theme.text)
                }

                Spacer()

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(theme.primary)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .padding(.leading, 44)

            Button {
                showingDocument = document
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                    Text(linkText)
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(theme.primary)
            }
            .padding(.leading, 44)
        }
        .glassCard()
    }
}

// MARK: - Legal Document Viewer

struct LegalDocumentView: View {
    let document: PrivacyConsentView.LegalDocument
    @EnvironmentObject var theme: ThemeService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            MarkdownWebView(markdown: loadMarkdown(), theme: theme)
                .screenBackground()
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .foregroundColor(.white)
                    }
                }
        }
    }

    private func loadMarkdown() -> String {
        let candidates = ["legal", "config/legal"]
        for subdirectory in candidates {
            if let url = Bundle.main.url(forResource: document.fileName, withExtension: "md", subdirectory: subdirectory),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return "Document could not be loaded. Please contact privacy@noongil.ai for a copy."
    }
}

// MARK: - Markdown Web View

private struct MarkdownWebView: UIViewRepresentable {
    let markdown: String
    let theme: ThemeService

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = markdownToHTML(markdown)
        let bg = "rgba(255,255,255,0.9)"
        let text = "#1E293B"
        let textSecondary = "#64748B"
        let primary = theme.primary.hexString ?? "#007AFF"
        let surface = "rgba(255,255,255,0.6)"

        let page = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, SF Pro Text, sans-serif;
            font-size: 14px; line-height: 1.5;
            color: \(text); background: \(bg);
            padding: 16px; margin: 0;
            -webkit-text-size-adjust: 100%;
        }
        h1 { font-size: 20px; margin: 24px 0 8px; }
        h2 { font-size: 17px; margin: 20px 0 6px; }
        h3 { font-size: 15px; margin: 16px 0 4px; }
        p { margin: 8px 0; }
        a { color: \(primary); }
        hr { border: none; border-top: 1px solid \(textSecondary); margin: 16px 0; opacity: 0.3; }
        ul, ol { padding-left: 20px; margin: 8px 0; }
        li { margin: 4px 0; }
        table {
            width: 100%; border-collapse: collapse;
            margin: 12px 0; font-size: 13px;
        }
        th {
            background: \(surface); text-align: left;
            padding: 8px 10px; font-weight: 600;
            border-bottom: 2px solid \(textSecondary);
        }
        td {
            padding: 8px 10px; vertical-align: top;
            border-bottom: 1px solid \(surface);
        }
        tr:last-child td { border-bottom: none; }
        </style></head><body>\(html)</body></html>
        """
        webView.loadHTMLString(page, baseURL: nil)
    }

    /// Lightweight markdown → HTML (handles headings, bold, italic, tables, lists, hrs, links, paragraphs)
    private func markdownToHTML(_ md: String) -> String {
        var html = ""
        var inTable = false
        var isFirstTableRow = true
        var inList = false
        var lines = md.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                if inList { html += "</ul>"; inList = false }
                if inTable { html += "</tbody></table>"; inTable = false }
                i += 1
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                if inList { html += "</ul>"; inList = false }
                if inTable { html += "</tbody></table>"; inTable = false }
                html += "<hr>"
                i += 1
                continue
            }

            // Headings
            if trimmed.hasPrefix("###") {
                if inTable { html += "</tbody></table>"; inTable = false }
                html += "<h3>\(inline(String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))))</h3>"
                i += 1; continue
            }
            if trimmed.hasPrefix("##") {
                if inTable { html += "</tbody></table>"; inTable = false }
                html += "<h2>\(inline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h2>"
                i += 1; continue
            }
            if trimmed.hasPrefix("# ") {
                if inTable { html += "</tbody></table>"; inTable = false }
                html += "<h1>\(inline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h1>"
                i += 1; continue
            }

            // Table rows
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                // Check if this is a separator row
                let inner = trimmed.dropFirst().dropLast()
                let isSeparator = inner.allSatisfy { $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }

                if isSeparator {
                    i += 1; continue
                }

                let cells = trimmed.split(separator: "|", omittingEmptySubsequences: true)
                    .map { inline(String($0.trimmingCharacters(in: .whitespaces))) }

                if !inTable {
                    html += "<table><thead><tr>"
                    for cell in cells { html += "<th>\(cell)</th>" }
                    html += "</tr></thead><tbody>"
                    inTable = true
                    isFirstTableRow = true
                } else {
                    html += "<tr>"
                    for cell in cells { html += "<td>\(cell)</td>" }
                    html += "</tr>"
                }
                i += 1; continue
            }

            // Close table if we hit a non-table line
            if inTable { html += "</tbody></table>"; inTable = false }

            // List items
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList { html += "<ul>"; inList = true }
                html += "<li>\(inline(String(trimmed.dropFirst(2))))</li>"
                i += 1; continue
            }

            // Close list if non-list line
            if inList { html += "</ul>"; inList = false }

            // Paragraph
            html += "<p>\(inline(trimmed))</p>"
            i += 1
        }

        if inList { html += "</ul>" }
        if inTable { html += "</tbody></table>" }
        return html
    }

    /// Inline markdown: bold, italic, links
    private func inline(_ text: String) -> String {
        var s = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        // Bold
        s = s.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        // Italic
        s = s.replacingOccurrences(
            of: "\\*(.+?)\\*",
            with: "<em>$1</em>",
            options: .regularExpression
        )
        // Links [text](url)
        s = s.replacingOccurrences(
            of: "\\[(.+?)\\]\\((.+?)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        return s
    }
}

// MARK: - Color Hex Helper

private extension Color {
    var hexString: String? {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
