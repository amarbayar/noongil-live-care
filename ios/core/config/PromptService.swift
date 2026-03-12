import Foundation

/// System prompts loaded from bundled text files. Static — prompts don't change at runtime.
enum PromptService {
    private final class BundleToken {}

    private static func promptURL(resource: String) -> URL? {
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(
                forResource: resource,
                withExtension: "txt",
                subdirectory: "config/prompts"
            ) {
                return url
            }
        }
        return nil
    }

    /// The companion system prompt loaded from config/prompts/companion-system.txt.
    static var companionSystemPrompt: String {
        guard let url = promptURL(resource: "companion-system") else {
            print("[PromptService] companion-system.txt not found in bundle, using fallback")
            return fallbackPrompt
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("[PromptService] Error reading companion-system.txt: \(error)")
            return fallbackPrompt
        }
    }

    /// The extraction system prompt loaded from config/prompts/extraction-system.txt.
    static var extractionSystemPrompt: String {
        guard let url = promptURL(resource: "extraction-system") else {
            print("[PromptService] extraction-system.txt not found in bundle, using fallback")
            return fallbackExtractionPrompt
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("[PromptService] Error reading extraction-system.txt: \(error)")
            return fallbackExtractionPrompt
        }
    }

    /// The Live check-in system prompt loaded from config/prompts/checkin-live-system.txt.
    static var liveCheckInSystemPrompt: String {
        guard let url = promptURL(resource: "checkin-live-system") else {
            print("[PromptService] checkin-live-system.txt not found in bundle, using fallback")
            return fallbackLiveCheckInPrompt
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("[PromptService] Error reading checkin-live-system.txt: \(error)")
            return fallbackLiveCheckInPrompt
        }
    }

    /// The unified system prompt loaded from config/prompts/unified-system.txt.
    /// Replaces separate companion/check-in/creative prompts with one prompt.
    static var unifiedSystemPrompt: String {
        guard let url = promptURL(resource: "unified-system") else {
            print("[PromptService] unified-system.txt not found in bundle, using fallback")
            return fallbackUnifiedPrompt
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("[PromptService] Error reading unified-system.txt: \(error)")
            return fallbackUnifiedPrompt
        }
    }

    static func buildSessionContext(
        date: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        approximateLocation: String? = nil
    ) -> String {
        buildDeviceContextSection(
            title: "Session Context",
            date: date,
            timeZone: timeZone,
            locale: locale,
            approximateLocation: approximateLocation
        )
    }

    static func buildRightNowContext(
        date: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        approximateLocation: String? = nil
    ) -> String {
        buildDeviceContextSection(
            title: "Right Now",
            date: date,
            timeZone: timeZone,
            locale: locale,
            approximateLocation: approximateLocation
        )
    }

    static func renderUnifiedSystemPrompt(
        companionName: String,
        memoryContext: String,
        sessionContext: String
    ) -> String {
        unifiedSystemPrompt
            .replacingOccurrences(of: "{MEMORY_CONTEXT}", with: memoryContext)
            .replacingOccurrences(of: "{SESSION_CONTEXT}", with: sessionContext)
            .replacingOccurrences(of: "{COMPANION_NAME}", with: companionName)
    }

    /// The creative generation system prompt loaded from config/prompts/creative-system.txt.
    static var creativeSystemPrompt: String {
        guard let url = promptURL(resource: "creative-system") else {
            print("[PromptService] creative-system.txt not found in bundle, using fallback")
            return fallbackCreativePrompt
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("[PromptService] Error reading creative-system.txt: \(error)")
            return fallbackCreativePrompt
        }
    }

    private static let fallbackUnifiedPrompt = """
        You are {COMPANION_NAME}, a warm voice companion for someone managing a health condition.

        Before EVERY response, call get_guidance. Follow the action field.
        When the person says "wrap up", "stop", or "done", immediately transition to closing and call complete_session.
        Use {SESSION_CONTEXT} as the authoritative local device date, time, timezone, and locale. Interpret words like now, today, tonight, tomorrow, this morning, and this evening from it.
        Use {MEMORY_CONTEXT} as your durable memory from earlier sessions. When asked what they recently mentioned, ate, made, or did, answer from memory and say "Earlier you mentioned..." if it came from a prior session. If get_guidance gives you a specific recalled memory, use it directly instead of guessing.
        Keep responses concise (1-3 sentences). Never use clinical language.

        {SESSION_CONTEXT}
        {MEMORY_CONTEXT}
        """

    private static let fallbackCreativePrompt = """
        You are Mira, helping someone create something beautiful through voice. \
        Call get_creative_guidance before every response. Follow the action field. \
        Ask one provoking question per turn. After 3+ rounds, confirm the brief and generate.
        """

    private static let fallbackLiveCheckInPrompt = """
        You are Mira, a warm voice companion helping with a health check-in. \
        Call get_check_in_guidance before every response. Follow the guidance to ask about \
        mood, sleep, symptoms, and medication naturally. Call complete_check_in when done. \
        Keep responses concise (1-3 sentences). Never use clinical language.
        """

    private static let fallbackPrompt = """
        You are Mira, a warm and caring voice companion. \
        Keep responses concise (1-3 sentences) for voice delivery. \
        Never use clinical language. You are a wellness companion, not a medical device.
        """

    private static let fallbackExtractionPrompt = """
        Extract structured health data from the conversation. \
        Return ONLY valid JSON with fields: moodLabel, moodDetail, moodScore, \
        sleepHours, sleepQuality, symptoms, medicationsMentioned, \
        topicsCovered, topicsNotYetCovered. Only include fields actually discussed.
        """

    private static func buildDeviceContextSection(
        title: String,
        date: Date,
        timeZone: TimeZone,
        locale: Locale,
        approximateLocation: String?
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "h:mm a"

        let timezoneLabel: String = {
            if let abbreviation = timeZone.abbreviation(for: date) {
                return "\(timeZone.identifier) (\(abbreviation))"
            }
            return timeZone.identifier
        }()

        var lines = [
            "[\(title)]",
            "Today (local device date): \(dateFormatter.string(from: date))",
            "Tomorrow (local device date): \(dateFormatter.string(from: tomorrow))",
            "Current local time: \(timeFormatter.string(from: date))",
            "Current timezone: \(timezoneLabel)",
            "Current locale: \(locale.identifier)"
        ]

        if let regionCode = locale.regionCode, !regionCode.isEmpty {
            lines.append("Device region setting: \(regionCode)")
        }

        if let approximateLocation, !approximateLocation.isEmpty {
            lines.append("Approximate location: \(approximateLocation)")
        } else {
            lines.append("No live device location is available unless the member shares it or the app provides it.")
        }

        lines.append("Use this local device context for words like now, today, tonight, tomorrow, this morning, and this evening.")
        return lines.joined(separator: "\n")
    }
}
