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
    /// The models offered in the settings (ID, name), in fallback order. Change here to switch models.
    public static let choices: [(id: String, name: String)] = [
        ("gemini-3.8-flash", "Gemini 3.8 Flash"),
        ("gemini-3.6-flash", "Gemini 3.6 Flash"),
        ("gemini-3.5-flash-lite", "Gemini 3.5 Flash-Lite")
    ]
    /// Default model.
    public static var model: String { choices[0].id }

    /// The chosen model first, then the others in case it is overloaded, too slow or out of free quota.
    public static func models(preferred: String) -> [String] {
        let all = choices.map(\.id)
        return all.contains(preferred) ? [preferred] + all.filter { $0 != preferred } : all
    }
    /// Gemini 3.8 Flash accepts low, medium (default) and high; "minimal" is rejected.
    public static let thinkingLevel = "low"
    public static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!

    static let meaningKey = "significato"
    static let contextKey = "contesto"

    // MARK: Request

    public static func request(term: String, context: String?, apiKey: String,
                               model: String = model) -> URLRequest {
        post(body(term: term, context: context), apiKey: apiKey, model: model)
    }

    /// A tiny message to check that a newly entered key works.
    public static func testRequest(apiKey: String, model: String = model) -> URLRequest {
        post(["contents": [["role": "user", "parts": [["text": "Rispondi solo con la parola: ok"]]]],
              "generationConfig": ["thinkingConfig": ["thinkingLevel": thinkingLevel]]],
             apiKey: apiKey, model: model)
    }

    static func post(_ body: [String: Any], apiKey: String, model: String) -> URLRequest {
        var request = URLRequest(url: endpoint.appendingPathComponent("\(model):generateContent"))
        request.httpMethod = "POST"
        // An overloaded model can hang for a long time before answering 503: better to move on.
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The key goes in a header, never in the URL.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
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
        Sei un tutor esperto che aiuta uno studente universitario italiano di ingegneria a capire un libro \
        tecnico in inglese. Rispondi sempre in italiano, senza Markdown.
        Dai informazioni concrete e utili per studiare, non definizioni vaghe: se il termine è un composto \
        chimico scrivi la formula e cos'è; se è una grandezza fisica scrivi simbolo, unità di misura SI ed \
        eventuale formula; se è una sigla scrivila per esteso; se è un componente o un processo spiega a cosa \
        serve e come funziona; aggiungi un valore tipico o un esempio quando aiuta. Indica il termine italiano \
        corretto quando esiste. Scrivi formule e simboli in testo semplice con caratteri Unicode \
        (es. H₂O, N₂H₄, m/s², Isp = F/(ṁ·g₀)). Non inventare dati: se non sei sicuro di un valore, omettilo.
        Sii denso ma breve: niente frasi di riempimento, non ripetere la domanda.
        """

    static func prompt(term: String, context: String?) -> String {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let meaning = """
            - "\(meaningKey)": cos'è il termine in generale, con i dati concreti utili \
            (formula, simbolo, unità, sigla per esteso, funzione), in 2-4 frasi.
            """
        if sentence.isEmpty {
            return """
                Termine inglese: "\(term)"
                (La frase in cui compare non è disponibile.)

                Rispondi in JSON con due campi:
                \(meaning)
                - "\(contextKey)": come e dove si usa di solito in un testo tecnico, in 1-3 frasi.
                """
        }
        return """
            Termine inglese: "\(term)"
            Frase in cui compare: "\(sentence)"

            Rispondi in JSON con due campi:
            \(meaning)
            - "\(contextKey)": cosa vuole dire davvero l'autore in questa frase: l'idea, il concetto \
            tecnico o il fenomeno che sta descrivendo e perché il termine conta lì, collegandolo \
            all'argomento del testo, in 1-3 frasi. Non tradurre né parafrasare la frase parola per \
            parola: interpretala e spiegane il senso, come farebbe un professore a uno studente.
            """
    }

    // MARK: Response

    /// Reads a successful (HTTP 200) `generateContent` response.
    public static func parse(_ data: Data) throws(ExplanationError) -> WordExplanation {
        try explanation(fromModelText: answerText(data))
    }

    /// Reads the answer to `testRequest`: any text means the key works.
    public static func parseTest(_ data: Data) throws(ExplanationError) {
        guard try !answerText(data).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .badResponse }
    }

    /// The answer's text, without thought parts.
    static func answerText(_ data: Data) throws(ExplanationError) -> String {
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
        return text
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

    /// Errors tied to one model, where another model may still answer.
    public static func shouldTryNextModel(after error: ExplanationError) -> Bool {
        switch error {
        case .unavailable, .timedOut, .quotaExceeded, .modelNotFound, .http: true
        case .missingKey, .invalidKey, .offline, .blocked, .badResponse: false
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
