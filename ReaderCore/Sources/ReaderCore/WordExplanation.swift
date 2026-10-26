import Foundation

/// The two short parts of an AI explanation of a circled term.
public struct WordExplanation: Equatable, Sendable {
    /// General meaning of the term.
    public let meaning: String
    /// What it means in the sentence where it was circled.
    public let inContext: String

    public init(meaning: String, inContext: String) {
        self.meaning = meaning
        self.inContext = inContext
    }
}

/// Short, user-facing reasons an explanation couldn't be obtained.
public enum ExplanationError: Error, Equatable, Sendable {
    case missingKey
    case invalidKey
    case quotaExceeded
    case offline
    case timedOut
    case unavailable
    case modelNotFound
    case blocked
    case badResponse
    case http(Int)

    public var message: String {
        switch self {
        case .missingKey: "Serve una chiave API di Google AI Studio: aggiungila nelle impostazioni."
        case .invalidKey: "La chiave API non è valida. Controllala nelle impostazioni."
        case .quotaExceeded: "Limite gratuito raggiunto. Riprova tra un po'."
        case .offline: "Sei offline. Collegati a internet e riprova."
        case .timedOut: "Il servizio non ha risposto in tempo. Riprova."
        case .unavailable: "Il servizio è sovraccarico in questo momento. Riprova tra poco."
        case .modelNotFound: "Il modello IA non è disponibile per questa chiave."
        case .blocked: "Il servizio non ha voluto rispondere su questo testo."
        case .badResponse: "Risposta non comprensibile. Riprova."
        case .http(let code): "Errore del servizio (codice \(code)). Riprova."
        }
    }
}

/// Builds requests to and reads responses from the Gemini API (`generateContent`, REST).
public enum GeminiExplainer {
    /// Change here to switch model.
    public static let model = "gemini-3.8-flash"
    /// Gemini 3.8 Flash accepts low, medium (default) and high; "minimal" is rejected.
    public static let thinkingLevel = "low"
    public static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!

    static let meaningKey = "significato"
    static let contextKey = "contesto"

    // MARK: Request

    public static func request(term: String, context: String?, apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpoint.appendingPathComponent("\(model):generateContent"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The key goes in a header, never in the URL.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body(term: term, context: context),
                                                       options: [.sortedKeys])
        return request
    }

    static func body(term: String, context: String?) -> [String: Any] {
        [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": prompt(term: term, context: context)]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        meaningKey: ["type": "STRING"],
                        contextKey: ["type": "STRING"]
                    ],
                    "required": [meaningKey, contextKey],
                    "propertyOrdering": [meaningKey, contextKey]
                ],
                "thinkingConfig": ["thinkingLevel": thinkingLevel]
            ]
        ]
    }

    static let systemPrompt = """
        Aiuti uno studente italiano che legge un libro tecnico in inglese. \
        Rispondi sempre in italiano, in modo chiaro e breve, senza formattazione Markdown.
        """

    static func prompt(term: String, context: String?) -> String {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if sentence.isEmpty {
            return """
                Termine inglese: "\(term)"
                (La frase in cui compare non è disponibile.)

                Rispondi in JSON con due campi:
                - "\(meaningKey)": il significato generale del termine, in 1 o 2 frasi.
                - "\(contextKey)": come si usa di solito in un testo tecnico, in 1 o 2 frasi.
                """
        }
        return """
            Termine inglese: "\(term)"
            Frase in cui compare: "\(sentence)"

            Rispondi in JSON con due campi:
            - "\(meaningKey)": il significato generale del termine, in 1 o 2 frasi.
            - "\(contextKey)": cosa significa il termine in questa frase, in 1 o 2 frasi.
            """
    }

    // MARK: Response

    /// Reads a successful (HTTP 200) `generateContent` response.
    public static func parse(_ data: Data) throws(ExplanationError) -> WordExplanation {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .badResponse
        }
        if let feedback = root["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil {
            throw .blocked
        }
        guard let candidate = (root["candidates"] as? [[String: Any]])?.first else { throw .blocked }
        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
        if text.isEmpty, let reason = candidate["finishReason"] as? String,
           ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "RECITATION"].contains(reason) {
            throw .blocked
        }
        return try explanation(fromModelText: text)
    }

    /// The model's JSON, tolerating code fences or text around it.
    static func explanation(fromModelText text: String) throws(ExplanationError) -> WordExplanation {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let object = (try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8))) as? [String: Any]
        else { throw .badResponse }
        let meaning = (object[meaningKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let inContext = (object[contextKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !meaning.isEmpty, !inContext.isEmpty else { throw .badResponse }
        return WordExplanation(meaning: meaning, inContext: inContext)
    }

    /// Maps a non-200 response to a short reason.
    public static func error(status: Int, body: Data) -> ExplanationError {
        let error = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? [String: Any]
        let message = (error?["message"] as? String ?? "").lowercased()
        let reasons = (error?["details"] as? [[String: Any]] ?? []).compactMap { $0["reason"] as? String }
        switch status {
        case 400 where reasons.contains("API_KEY_INVALID") || message.contains("api key"):
            return .invalidKey
        case 401, 403:
            return .invalidKey
        case 404:
            return .modelNotFound
        case 429:
            return .quotaExceeded
        case 500, 502, 503, 504:
            return .unavailable
        default:
            return .http(status)
        }
    }

    public static func error(for urlError: URLError) -> ExplanationError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            .offline
        case .timedOut:
            .timedOut
        default:
            .unavailable
        }
    }
}
