import Foundation

enum Language: String, CaseIterable {
    case mongolian = "Mongolian"
    case english = "English"
}

enum AudioEnhancementMode: String, CaseIterable {
    case none           = "None"
    case denoiseOnly    = "Denoise"
    case sbrOnly        = "SBR"
    case sbrThenDenoise = "SBR+Denoise"
    case denoiseThenSbr = "Denoise+SBR"
}

enum PipelineMode: String, CaseIterable {
    case local    = "Local"      // VAD → ASR → Gemini REST → TTS (on-device processing)
    case live     = "Live"       // Gemini Live WebSocket (native audio in/out)
    case liveText = "Live+TTS"   // Gemini Live (audio in, text out) → on-device TTS
}

enum Config {
    // MARK: - Gemini API

    /// Gemini API key — loaded from Info.plist (set via xcconfig / build settings)
    static let geminiAPIKey: String = {
        if let key = Bundle.main.infoDictionary?["GEMINI_API_KEY"] as? String, !key.isEmpty, !key.hasPrefix("$(") {
            return key
        }
        #if DEBUG
        // Fallback for local development — set GEMINI_API_KEY env var
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return key
        }
        #endif
        return ""
    }()
    static let geminiModel = "gemini-3.1-flash-lite-preview"
    static let geminiImageModel = "imagen-4.0-generate-001"
    static let geminiImageEditModel = "gemini-3.1-flash-image-preview"
    static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta"

    // MARK: - Lyria RealTime (Streaming Music Generation)

    static let lyriaRealtimeModel = "lyria-realtime-exp"
    static let lyriaRealtimeBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateMusic"
    static let lyriaRealtimeSampleRate: Int = 44_100

    // MARK: - Backend API

    /// Backend base URL — loaded from Info.plist (set via xcconfig / build settings)
    /// Falls back to local network IP for on-device development.
    static let backendBaseURL: String = {
        if let url = Bundle.main.infoDictionary?["BACKEND_BASE_URL"] as? String, !url.isEmpty, !url.hasPrefix("$(") {
            return url
        }
        return "http://127.0.0.1:8080"
    }()

    static let publicDashboardURL: String = {
        if let url = Bundle.main.infoDictionary?["PUBLIC_DASHBOARD_URL"] as? String, !url.isEmpty, !url.hasPrefix("$(") {
            return url
        }
        return backendBaseURL
    }()

    // MARK: - Gemini Live (Streaming Native Audio)

    /// Gemini Live uses the same API key
    static let geminiLiveModel = "gemini-2.5-flash-native-audio-preview-12-2025"
    static let geminiLiveBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    static let geminiLiveOutputSampleRate: Int = 24_000

    /// Available voices for Gemini Live native audio
    struct LiveVoice: Identifiable {
        let id: String   // voice name used in API
        let label: String // display name
    }

    static let liveVoices: [LiveVoice] = [
        LiveVoice(id: "Puck", label: "Puck (M)"),
        LiveVoice(id: "Charon", label: "Charon (M)"),
        LiveVoice(id: "Fenrir", label: "Fenrir (M)"),
        LiveVoice(id: "Orus", label: "Orus (M)"),
        LiveVoice(id: "Aoede", label: "Aoede (F)"),
        LiveVoice(id: "Kore", label: "Kore (F)"),
        LiveVoice(id: "Leda", label: "Leda (F)"),
        LiveVoice(id: "Zephyr", label: "Zephyr (F)"),
    ]

    // MARK: - ASR Model Paths (Delden Zipformer)

    static var asrEncoderPath: String {
        Bundle.main.path(forResource: "encoder.int8", ofType: "onnx", inDirectory: "models") ?? ""
    }

    static var asrDecoderPath: String {
        Bundle.main.path(forResource: "decoder", ofType: "onnx", inDirectory: "models") ?? ""
    }

    static var asrJoinerPath: String {
        Bundle.main.path(forResource: "joiner.int8", ofType: "onnx", inDirectory: "models") ?? ""
    }

    static var asrTokensPath: String {
        Bundle.main.path(forResource: "tokens", ofType: "txt", inDirectory: "models") ?? ""
    }

    // MARK: - ASR Model Paths (Moonshine Tiny — English)

    static var moonshinePreprocessorPath: String {
        Bundle.main.path(forResource: "preprocess", ofType: "onnx", inDirectory: "models/moonshine") ?? ""
    }

    static var moonshineEncoderPath: String {
        Bundle.main.path(forResource: "encode.int8", ofType: "onnx", inDirectory: "models/moonshine") ?? ""
    }

    static var moonshineUncachedDecoderPath: String {
        Bundle.main.path(forResource: "uncached_decode.int8", ofType: "onnx", inDirectory: "models/moonshine") ?? ""
    }

    static var moonshineCachedDecoderPath: String {
        Bundle.main.path(forResource: "cached_decode.int8", ofType: "onnx", inDirectory: "models/moonshine") ?? ""
    }

    static var moonshineTokensPath: String {
        Bundle.main.path(forResource: "tokens", ofType: "txt", inDirectory: "models/moonshine") ?? ""
    }

    // MARK: - TTS Model Paths (Tsetsen Piper)

    static var ttsModelPath: String {
        Bundle.main.path(forResource: "tsetsen", ofType: "onnx", inDirectory: "models") ?? ""
    }

    static var ttsConfigPath: String {
        // Piper config is named model.onnx.json
        Bundle.main.path(forResource: "tsetsen.onnx", ofType: "json", inDirectory: "models") ?? ""
    }

    static var ttsDataDir: String {
        Bundle.main.path(forResource: "espeak-ng-data", ofType: nil) ?? ""
    }

    static var ttsTokensPath: String {
        // Some Piper models use a separate tokens.txt; if your model bundles it, set the path here
        Bundle.main.path(forResource: "tsetsen-tokens", ofType: "txt", inDirectory: "models") ?? ""
    }

    // MARK: - TTS Model Paths (Kokoro — English)

    static var kokoroModelPath: String {
        Bundle.main.path(forResource: "model", ofType: "onnx", inDirectory: "models/kokoro") ?? ""
    }

    static var kokoroVoicesPath: String {
        Bundle.main.path(forResource: "voices", ofType: "bin", inDirectory: "models/kokoro") ?? ""
    }

    static var kokoroTokensPath: String {
        Bundle.main.path(forResource: "tokens", ofType: "txt", inDirectory: "models/kokoro") ?? ""
    }

    static var kokoroDataDir: String {
        // Kokoro reuses the app-level espeak-ng-data
        Bundle.main.path(forResource: "espeak-ng-data", ofType: nil) ?? ""
    }

    static var kokoroLexiconPath: String {
        Bundle.main.path(forResource: "lexicon-us-en", ofType: "txt", inDirectory: "models/kokoro") ?? ""
    }

    // MARK: - VAD Model Path (Silero)

    static var vadModelPath: String {
        Bundle.main.path(forResource: "silero_vad", ofType: "onnx", inDirectory: "models") ?? ""
    }

    // MARK: - Denoiser Model Path (GTCRN)

    static var denoiserModelPath: String {
        Bundle.main.path(forResource: "gtcrn_simple", ofType: "onnx", inDirectory: "models") ?? ""
    }

    // MARK: - TTS Speakers

    struct TTSSpeaker: Identifiable {
        let id: Int
        let name: String
    }

    static let tsetsenSpeakers: [TTSSpeaker] = [
        TTSSpeaker(id: 0, name: "Aida"), TTSSpeaker(id: 1, name: "Aimee"),
        TTSSpeaker(id: 2, name: "Anir (kid)"), TTSSpeaker(id: 3, name: "Blondie"),
        TTSSpeaker(id: 4, name: "Brian"), TTSSpeaker(id: 5, name: "Carlotta"),
        TTSSpeaker(id: 6, name: "David"), TTSSpeaker(id: 7, name: "Dominic"),
        TTSSpeaker(id: 8, name: "Ellen"), TTSSpeaker(id: 9, name: "Jerry"),
        TTSSpeaker(id: 10, name: "Jess"), TTSSpeaker(id: 11, name: "Liam"),
        TTSSpeaker(id: 12, name: "Monika"), TTSSpeaker(id: 13, name: "Rex"),
        TTSSpeaker(id: 14, name: "Spuds"), TTSSpeaker(id: 15, name: "Tamir (kid)"),
        TTSSpeaker(id: 16, name: "Xavier"),
    ]

    static let kokoroSpeakers: [TTSSpeaker] = [
        // American English Female
        TTSSpeaker(id: 0, name: "Alloy (F, US)"), TTSSpeaker(id: 1, name: "Aoede (F, US)"),
        TTSSpeaker(id: 2, name: "Bella (F, US)"), TTSSpeaker(id: 3, name: "Heart (F, US)"),
        TTSSpeaker(id: 4, name: "Jessica (F, US)"), TTSSpeaker(id: 5, name: "Kore (F, US)"),
        TTSSpeaker(id: 6, name: "Nicole (F, US)"), TTSSpeaker(id: 7, name: "Nova (F, US)"),
        TTSSpeaker(id: 8, name: "River (F, US)"), TTSSpeaker(id: 9, name: "Sarah (F, US)"),
        TTSSpeaker(id: 10, name: "Sky (F, US)"),
        // American English Male
        TTSSpeaker(id: 11, name: "Adam (M, US)"), TTSSpeaker(id: 12, name: "Echo (M, US)"),
        TTSSpeaker(id: 13, name: "Eric (M, US)"), TTSSpeaker(id: 14, name: "Fenrir (M, US)"),
        TTSSpeaker(id: 15, name: "Liam (M, US)"), TTSSpeaker(id: 16, name: "Michael (M, US)"),
        TTSSpeaker(id: 17, name: "Onyx (M, US)"), TTSSpeaker(id: 18, name: "Puck (M, US)"),
        TTSSpeaker(id: 19, name: "Santa (M, US)"),
        // British English
        TTSSpeaker(id: 20, name: "Alice (F, GB)"), TTSSpeaker(id: 21, name: "Emma (F, GB)"),
        TTSSpeaker(id: 22, name: "Isabella (F, GB)"), TTSSpeaker(id: 23, name: "Lily (F, GB)"),
        TTSSpeaker(id: 24, name: "Daniel (M, GB)"), TTSSpeaker(id: 25, name: "Fable (M, GB)"),
        TTSSpeaker(id: 26, name: "George (M, GB)"), TTSSpeaker(id: 27, name: "Lewis (M, GB)"),
    ]

    // MARK: - Audio

    static let asrSampleRate: Int = 16_000
    static let vadWindowSize: Int = 512
    static let vadThreshold: Float = 0.5

    // MARK: - Report Trigger Keywords

    /// Keywords that trigger the doctor visit report flow
    static let reportKeywords: [String] = [
        "prepare my doctor visit summary",
        "prepare my doctor summary",
        "doctor visit summary",
        "doctor summary",
        "health summary",
        "health report",
        "doctor visit report",
        "doctor report",
        "prepare a report",
        "prepare a summary",
        "summary for my doctor",
        "report for my doctor"
    ]

    /// Maps spoken period descriptions to day counts for report date range
    static let reportPeriodKeywords: [String: Int] = [
        "one week": 7,
        "a week": 7,
        "last week": 7,
        "past week": 7,
        "two weeks": 14,
        "last two weeks": 14,
        "past two weeks": 14,
        "three weeks": 21,
        "last month": 30,
        "past month": 30,
        "one month": 30,
        "a month": 30,
        "six weeks": 42,
        "two months": 60,
        "three months": 90,
        "since my last visit": 90,
        "last three months": 90,
        "past three months": 90
    ]

    // MARK: - Vision Trigger Keywords

    /// Keywords that trigger camera frame capture for multimodal Gemini request
    static let visionKeywords: [String] = [
        // English
        "what is this", "what do you see", "look at", "describe", "what's this",
        "what am i looking at", "tell me about this",
        // Mongolian
        "энэ юу вэ", "юу харж байна", "хар", "тайлбарла", "энэ юу",
        "харна уу", "юу байна"
    ]
}
