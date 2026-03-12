import Foundation

/// Localized strings loaded from bundled JSON. Supports language switching and variable interpolation.
@MainActor
final class StringsService: ObservableObject {

    @Published var strings: [String: String] = [:]
    @Published private(set) var currentLanguage: String = "en"

    // MARK: - Init

    init() {
        loadBundledStrings(language: "en")
    }

    // MARK: - Subscript

    subscript(key: String) -> String {
        strings[key] ?? key
    }

    // MARK: - Interpolation

    /// Returns the localized string for `key`, replacing `%variable%` placeholders with provided values.
    func localized(_ key: String, variables: [String: String] = [:]) -> String {
        var result = self[key]
        for (name, value) in variables {
            result = result.replacingOccurrences(of: "%\(name)%", with: value)
        }
        return result
    }

    // MARK: - Language Switching

    func switchLanguage(_ language: String) {
        guard language != currentLanguage else { return }
        loadBundledStrings(language: language)
    }

    // MARK: - Load from Bundle

    private func loadBundledStrings(language: String) {
        guard let url = Bundle.main.url(
            forResource: language,
            withExtension: "json",
            subdirectory: "config/strings"
        ) else {
            print("[StringsService] \(language).json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                print("[StringsService] Failed to parse \(language).json")
                return
            }
            strings = dict
            currentLanguage = language
        } catch {
            print("[StringsService] Error loading \(language).json: \(error)")
        }
    }
}
