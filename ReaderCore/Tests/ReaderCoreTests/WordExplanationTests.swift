import Foundation
import Testing
@testable import ReaderCore

private func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

private func response(text: String, thought: String? = nil) -> Data {
    var parts: [[String: Any]] = []
    if let thought { parts.append(["text": thought, "thought": true]) }
    parts.append(["text": text])
    return json(["candidates": [["content": ["role": "model", "parts": parts], "finishReason": "STOP"]]])
}

private func requestBody(_ request: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

struct WordExplanationTests {
    // MARK: Request

    @Test func requestTargetsModelWithKeyInHeader() {
        let request = GeminiExplainer.request(term: "stall", context: "The wing reached the stall angle.",
                                              apiKey: "SECRET")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiExplainer.model):generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "SECRET")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.absoluteString.contains("SECRET") == false)
    }

    @Test func requestAsksForLowThinkingAndJSON() {
        let body = requestBody(GeminiExplainer.request(term: "stall", context: nil, apiKey: "k"))
        let config = body["generationConfig"] as? [String: Any]
        #expect((config?["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String == "low")
        #expect(config?["responseMimeType"] as? String == "application/json")
        let schema = config?["responseSchema"] as? [String: Any]
        #expect(schema?["required"] as? [String] == ["significato", "contesto"])
        // Gemini 3 dropped the sampling parameters.
        #expect(config?["temperature"] == nil)
    }

    @Test func promptCarriesTermAndSentence() {
        let body = requestBody(GeminiExplainer.request(term: " stall ", context: "The wing reached the stall angle.",
                                                       apiKey: "k"))
        let contents = body["contents"] as? [[String: Any]]
        let text = ((contents?.first?["parts"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        #expect(text.contains("Termine inglese: \"stall\""))
        #expect(text.contains("Frase in cui compare: \"The wing reached the stall angle.\""))
        #expect(text.contains("in questa frase"))
        // Asks for concrete data, not vague definitions.
        let system = ((body["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String
        #expect(system?.contains("formula") == true)
        #expect(system?.contains("unità di misura") == true)
    }

    @Test func promptWithoutSentenceAsksForTypicalUse() {
        let text = GeminiExplainer.prompt(term: "stall", context: "  ")
        #expect(!text.contains("Frase in cui compare"))
        #expect(text.contains("non è disponibile"))
    }

    @Test func testRequestIsShortWithKeyInHeader() {
        let request = GeminiExplainer.testRequest(apiKey: "SECRET")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "SECRET")
        #expect(request.url?.absoluteString.hasSuffix("/\(GeminiExplainer.model):generateContent") == true)
        let body = requestBody(request)
        let config = body["generationConfig"] as? [String: Any]
        #expect((config?["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String == "low")
        #expect(config?["responseSchema"] == nil)
    }

    // MARK: Response

    @Test func parsesStructuredAnswer() throws {
        let data = response(text: #"{"significato": " Perdita di portanza. ", "contesto": "L'ala supera l'angolo critico."}"#)
        let explanation = try GeminiExplainer.parse(data)
        #expect(explanation == WordExplanation(meaning: "Perdita di portanza.",
                                               inContext: "L'ala supera l'angolo critico."))
    }

    @Test func skipsThoughtPartsAndCodeFences() throws {
        let data = response(text: "```json\n{\"significato\": \"A\", \"contesto\": \"B\"}\n```",
                            thought: "{\"significato\": \"pensiero\"}")
        #expect(try GeminiExplainer.parse(data) == WordExplanation(meaning: "A", inContext: "B"))
    }

    @Test func joinsSplitTextParts() throws {
        let data = json(["candidates": [["content": ["parts": [
            ["text": "{\"significato\": \"A\", "], ["text": "\"contesto\": \"B\"}"]
        ]]]]])
        #expect(try GeminiExplainer.parse(data) == WordExplanation(meaning: "A", inContext: "B"))
    }

    @Test func missingOrEmptyFieldIsBadResponse() {
        #expect(throws: ExplanationError.badResponse) {
            try GeminiExplainer.parse(response(text: #"{"significato": "A", "contesto": "  "}"#))
        }
        #expect(throws: ExplanationError.badResponse) {
            try GeminiExplainer.parse(response(text: "Non so."))
        }
        #expect(throws: ExplanationError.badResponse) {
            try GeminiExplainer.parse(Data("not json".utf8))
        }
    }

    @Test func blockedPromptOrCandidate() {
        #expect(throws: ExplanationError.blocked) {
            try GeminiExplainer.parse(json(["promptFeedback": ["blockReason": "SAFETY"]]))
        }
        #expect(throws: ExplanationError.blocked) {
            try GeminiExplainer.parse(json(["candidates": [["finishReason": "SAFETY"]]]))
        }
    }

    @Test func testAnswerNeedsSomeText() throws {
        try GeminiExplainer.parseTest(response(text: "ok"))
        #expect(throws: ExplanationError.badResponse) { try GeminiExplainer.parseTest(response(text: "  ")) }
        #expect(throws: ExplanationError.blocked) {
            try GeminiExplainer.parseTest(json(["promptFeedback": ["blockReason": "OTHER"]]))
        }
    }

    // MARK: Errors

    @Test func mapsHTTPErrors() {
        let badKey = json(["error": ["code": 400, "message": "API key not valid. Please pass a valid API key.",
                                     "status": "INVALID_ARGUMENT",
                                     "details": [["reason": "API_KEY_INVALID"]]]])
        #expect(GeminiExplainer.error(status: 400, body: badKey) == .invalidKey)
        #expect(GeminiExplainer.error(status: 400, body: json(["error": ["message": "Invalid value"]])) == .http(400))
        #expect(GeminiExplainer.error(status: 403, body: Data()) == .invalidKey)
        #expect(GeminiExplainer.error(status: 404, body: Data()) == .modelNotFound)
        #expect(GeminiExplainer.error(status: 429, body: Data()) == .quotaExceeded)
        #expect(GeminiExplainer.error(status: 503, body: Data()) == .unavailable)
    }

    @Test func fallsBackOnlyForModelErrors() {
        #expect(GeminiExplainer.models(preferred: "gemini-3.8-flash")
            == ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite"])
        #expect(GeminiExplainer.models(preferred: "gemini-3.5-flash-lite")
            == ["gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-3.6-flash"])
        // An unknown saved model falls back to the default order.
        #expect(GeminiExplainer.models(preferred: "gemini-1").first == GeminiExplainer.model)
        #expect(GeminiExplainer.request(term: "a", context: nil, apiKey: "k", model: "gemini-x").url?
            .absoluteString.hasSuffix("/gemini-x:generateContent") == true)
        for error in [ExplanationError.unavailable, .timedOut, .quotaExceeded, .modelNotFound] {
            #expect(GeminiExplainer.shouldTryNextModel(after: error))
        }
        for error in [ExplanationError.invalidKey, .offline, .blocked, .badResponse] {
            #expect(!GeminiExplainer.shouldTryNextModel(after: error))
        }
    }

    @Test func mapsNetworkErrors() {
        #expect(GeminiExplainer.error(for: URLError(.notConnectedToInternet)) == .offline)
        #expect(GeminiExplainer.error(for: URLError(.timedOut)) == .timedOut)
    }
}
