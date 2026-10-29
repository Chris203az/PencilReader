import Foundation
import Testing
@testable import ReaderCore

private func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

private func requestBody(_ request: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

struct AIProviderTests {
    private let prompt = AIPrompt(system: "Sistema", user: "Rispondi in json", json: true,
                                  schema: ["type": "OBJECT"], maxTokens: 300)

    // MARK: Settings

    @Test func featuresDefaultToGoogleAndKeepTheirOwnChoice() {
        let defaults = UserDefaults(suiteName: "AIProviderTests")!
        defaults.removePersistentDomain(forName: "AIProviderTests")
        #expect(AIFeature.ask.provider(in: defaults) == .google)
        defaults.set("deepseek", forKey: AIFeature.study.providerKey)
        #expect(AIFeature.study.provider(in: defaults) == .deepseek)
        #expect(AIFeature.ask.provider(in: defaults) == .google)
        defaults.set("sconosciuto", forKey: AIFeature.ask.providerKey)
        #expect(AIFeature.ask.provider(in: defaults) == .google)
    }

    @Test func modelsPutTheChosenOneFirst() {
        #expect(AIProvider.google.models(preferred: "gemini-3.5-flash-lite").first == "gemini-3.5-flash-lite")
        #expect(AIProvider.google.models(preferred: nil) == GeminiExplainer.choices.map(\.id))
        #expect(AIProvider.deepseek.models(preferred: "gemini-3.8-flash") == ["deepseek-flash"])
    }

    // MARK: DeepSeek

    @Test func deepSeekRequestUsesChatCompletionsWithBearerKey() {
        let request = AIRequests.request(prompt, provider: .deepseek, apiKey: "SECRET", model: "deepseek-flash")
        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer SECRET")
        #expect(request.url?.absoluteString.contains("SECRET") == false)
        let body = requestBody(request)
        #expect(body["model"] as? String == "deepseek-flash")
        #expect(body["stream"] as? Bool == false)
        #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_object")
        #expect(body["max_tokens"] as? Int == 300)
        let messages = body["messages"] as? [[String: String]]
        #expect(messages == [["role": "system", "content": "Sistema"], ["role": "user", "content": "Rispondi in json"]])
    }

    @Test func deepSeekPlainTextRequestHasNoJSONFormat() {
        let body = requestBody(AIRequests.request(AIPrompt(system: "s", user: "u"), provider: .deepseek,
                                                  apiKey: "k", model: "deepseek-flash"))
        #expect(body["response_format"] == nil)
        #expect(body["max_tokens"] == nil)
    }

    @Test func deepSeekAnswerSkipsReasoning() throws {
        let data = json(["choices": [["message": ["role": "assistant", "content": "{\"a\": 1}",
                                                  "reasoning_content": "Penso…"],
                                      "finish_reason": "stop"]]])
        #expect(try AIRequests.answerText(data, provider: .deepseek) == "{\"a\": 1}")
    }

    @Test func deepSeekFilteredOrMalformedAnswers() {
        let filtered = json(["choices": [["message": ["content": ""], "finish_reason": "content_filter"]]])
        #expect(throws: ExplanationError.blocked) { try AIRequests.answerText(filtered, provider: .deepseek) }
        #expect(throws: ExplanationError.badResponse) {
            try AIRequests.answerText(json(["choices": []]), provider: .deepseek)
        }
    }

    @Test func deepSeekErrors() {
        #expect(AIRequests.error(status: 401, body: Data(), provider: .deepseek) == .invalidKey)
        #expect(AIRequests.error(status: 402, body: Data(), provider: .deepseek) == .noCredit)
        #expect(AIRequests.error(status: 429, body: Data(), provider: .deepseek) == .quotaExceeded)
        #expect(AIRequests.error(status: 503, body: Data(), provider: .deepseek) == .unavailable)
        #expect(AIRequests.error(status: 422, body: Data(), provider: .deepseek) == .http(422))
        #expect(!GeminiExplainer.shouldTryNextModel(after: .noCredit))
    }

    @Test func deepSeekTestRequestIsTiny() {
        let body = requestBody(AIRequests.testRequest(provider: .deepseek, apiKey: "k", model: "deepseek-flash"))
        #expect(body["max_tokens"] as? Int == 10)
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
    }

    // MARK: Gemini

    @Test func geminiRequestCarriesSchemaAndLimit() {
        let request = AIRequests.request(prompt, provider: .google, apiKey: "SECRET", model: "gemini-3.8-flash")
        #expect(request.url?.absoluteString.hasSuffix("/gemini-3.8-flash:generateContent") == true)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "SECRET")
        let body = requestBody(request)
        let config = body["generationConfig"] as? [String: Any]
        #expect(config?["responseMimeType"] as? String == "application/json")
        #expect((config?["responseSchema"] as? [String: String]) == ["type": "OBJECT"])
        #expect(config?["maxOutputTokens"] as? Int == 300)
        let system = (body["systemInstruction"] as? [String: Any])?["parts"] as? [[String: String]]
        #expect(system?.first?["text"] == "Sistema")
    }

    @Test func geminiPlainTextRequestHasNoJSONConfig() {
        let body = requestBody(AIRequests.request(AIPrompt(system: "s", user: "u"), provider: .google,
                                                  apiKey: "k", model: "gemini-3.8-flash"))
        let config = body["generationConfig"] as? [String: Any]
        #expect(config?["responseMimeType"] == nil)
        #expect(config?["thinkingConfig"] != nil)
    }

    @Test func jsonObjectToleratesFences() {
        #expect(AIRequests.jsonObject(in: "```json\n{\"a\": 1}\n```")?["a"] as? Int == 1)
        #expect(AIRequests.jsonObject(in: "niente") == nil)
    }
}
