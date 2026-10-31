import Foundation

/// The AI services the app can talk to. To add one: a case here, its models and key page,
/// and its request/response format in `AIRequests`.
public enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case google
    case deepseek

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .google: "Google Gemini"
        case .deepseek: "DeepSeek"
        }
    }

    /// Shown next to the name in the settings.
    public var note: String {
        switch self {
        case .google: String(localized: "Gratuito con Google AI Studio")
        case .deepseek: String(localized: "A pagamento, serve credito sull'account")
        }
    }

    public var keyName: String {
        switch self {
        case .google: String(localized: "Chiave API di Google AI Studio")
        case .deepseek: String(localized: "Chiave API di DeepSeek")
        }
    }

    public var keyPage: (title: String, url: URL) {
        switch self {
        case .google: (String(localized: "Crea una chiave gratuita su Google AI Studio"), URL(string: "https://aistudio.google.com/apikey")!)
        case .deepseek: (String(localized: "Crea una chiave sulla piattaforma DeepSeek"), URL(string: "https://platform.deepseek.com/api_keys")!)
        }
    }

    /// The models offered in the settings (ID, name), in fallback order.
    public var choices: [(id: String, name: String)] {
        switch self {
        case .google: GeminiExplainer.choices
        case .deepseek: DeepSeekClient.choices
        }
    }

    public var defaultModel: String { choices[0].id }

    /// The chosen model first, then the others in case it is overloaded, too slow or out of quota.
    public func models(preferred: String?) -> [String] {
        let all = choices.map(\.id)
        guard let preferred, all.contains(preferred) else { return all }
        return [preferred] + all.filter { $0 != preferred }
    }
}

/// What the AI is used for; each one can use a different provider.
public enum AIFeature: String, CaseIterable, Identifiable, Sendable {
    /// "Chiedi all'IA" in the translation panel.
    case ask
    /// Everything else: concepts of the highlights, summaries, consolidation.
    case study

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ask: String(localized: "Chiedi all'IA")
        case .study: String(localized: "Altre funzioni")
        }
    }

    public var detail: String {
        switch self {
        case .ask: String(localized: "La spiegazione della parola cerchiata, nel riquadro della traduzione.")
        case .study: String(localized: "I concetti chiave del riepilogo e le altre funzioni di studio.")
        }
    }

    /// UserDefaults key of the provider chosen for this feature.
    public var providerKey: String { "aiProvider.\(rawValue)" }

    /// The chosen provider; Google until another is picked.
    public func provider(in defaults: UserDefaults = .standard) -> AIProvider {
        defaults.string(forKey: providerKey).flatMap(AIProvider.init(rawValue:)) ?? .google
    }
}

/// A request to any provider: instructions, the user's text and the answer's form.
public struct AIPrompt: Sendable {
    public var system: String
    public var user: String
    /// Asks for a JSON object. With DeepSeek the word "json" must appear in the prompt.
    public var json: Bool
    /// Gemini `responseSchema` for the JSON, encoded; other providers rely on the prompt.
    public var schemaJSON: Data?
    public var maxTokens: Int?

    /// Gemini `responseSchema` for the JSON; other providers rely on the prompt.
    public var schema: [String: Any]? {
        schemaJSON.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    }

    public init(system: String, user: String, json: Bool = false, schema: [String: Any]? = nil,
                maxTokens: Int? = nil) {
        self.system = system
        self.user = user
        self.json = json
        self.schemaJSON = schema.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        self.maxTokens = maxTokens
    }
}

/// Builds requests and reads answers for each provider.
public enum AIRequests {
    public static func request(_ prompt: AIPrompt, provider: AIProvider, apiKey: String,
                               model: String) -> URLRequest {
        switch provider {
        case .google: GeminiExplainer.request(prompt, apiKey: apiKey, model: model)
        case .deepseek: DeepSeekClient.request(prompt, apiKey: apiKey, model: model)
        }
    }

    /// A tiny message to check that a newly entered key works.
    public static func testRequest(provider: AIProvider, apiKey: String, model: String) -> URLRequest {
        switch provider {
        case .google: GeminiExplainer.testRequest(apiKey: apiKey, model: model)
        case .deepseek: DeepSeekClient.testRequest(apiKey: apiKey, model: model)
        }
    }

    /// The text of a successful (HTTP 200) answer, without reasoning.
    public static func answerText(_ data: Data, provider: AIProvider) throws(ExplanationError) -> String {
        switch provider {
        case .google: try GeminiExplainer.answerText(data)
        case .deepseek: try DeepSeekClient.answerText(data)
        }
    }

    /// Maps a non-200 response to a short reason.
    public static func error(status: Int, body: Data, provider: AIProvider) -> ExplanationError {
        switch provider {
        case .google: GeminiExplainer.error(status: status, body: body)
        case .deepseek: DeepSeekClient.error(status: status, body: body)
        }
    }

    /// The JSON object in a model's text, tolerating code fences or text around it.
    public static func jsonObject(in text: String) -> [String: Any]? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8))) as? [String: Any]
    }
}

/// DeepSeek's OpenAI-style `chat/completions` API (api-docs.deepseek.com).
public enum DeepSeekClient {
    /// `deepseek-flash` is served by DeepSeek-V4.1-Flash-1017.
    public static let choices: [(id: String, name: String)] = [
        ("deepseek-flash", "DeepSeek V4.1 Flash")
    ]
    public static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    /// Thinking is on by default at "high"; "low" keeps answers quick.
    public static let reasoningEffort = "low"

    static func request(_ prompt: AIPrompt, apiKey: String, model: String) -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": prompt.system],
                         ["role": "user", "content": prompt.user]],
            "stream": false,
            "thinking": ["type": "enabled"],
            "reasoning_effort": reasoningEffort
        ]
        if prompt.json { body["response_format"] = ["type": "json_object"] }
        if let maxTokens = prompt.maxTokens { body["max_tokens"] = maxTokens }
        return post(body, apiKey: apiKey)
    }

    static func testRequest(apiKey: String, model: String) -> URLRequest {
        post(["model": model,
              "messages": [["role": "user", "content": "Rispondi solo con la parola: ok"]],
              "stream": false,
              "thinking": ["type": "disabled"],
              "max_tokens": 10],
             apiKey: apiKey)
    }

    static func post(_ body: [String: Any], apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Only one model to fall back on: give it longer than Gemini's.
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// The answer's `content`; the reasoning comes separately in `reasoning_content`.
    static func answerText(_ data: Data) throws(ExplanationError) -> String {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choice = (root["choices"] as? [[String: Any]])?.first
        else { throw .badResponse }
        let text = (choice["message"] as? [String: Any])?["content"] as? String ?? ""
        if text.isEmpty, (choice["finish_reason"] as? String) == "content_filter" { throw .blocked }
        return text
    }

    static func error(status: Int, body: Data) -> ExplanationError {
        switch status {
        case 401, 403: .invalidKey
        case 402: .noCredit
        case 404: .modelNotFound
        case 429: .quotaExceeded
        case 500, 502, 503, 504: .unavailable
        default: .http(status)
        }
    }
}
