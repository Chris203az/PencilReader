import Foundation
import ReaderCore

/// Sends prompts to the provider chosen for each feature in the AI settings, with its key,
/// moving on to the provider's other models when one is overloaded, too slow or out of quota.
@MainActor
enum AIClient {
    /// UserDefaults key of the model chosen for a provider (Google's predates the other providers).
    static func modelKey(_ provider: AIProvider) -> String {
        provider == .google ? "aiModel" : "aiModel.\(provider.rawValue)"
    }

    static func hasKey(for feature: AIFeature) -> Bool {
        APIKeyStore.shared.hasKey(for: feature.provider())
    }

    /// The answer's text for `feature`, without reasoning; the caller reads it.
    static func ask(_ prompt: AIPrompt, for feature: AIFeature) async throws(ExplanationError) -> String {
        let provider = feature.provider()
        guard let apiKey = APIKeyStore.shared.key(for: provider) else { throw .missingKey }
        return try await firstAnswer(provider) { model in
            try await AIRequests.answerText(send(AIRequests.request(prompt, provider: provider, apiKey: apiKey,
                                                                    model: model), provider, model),
                                            provider: provider)
        }
    }

    /// "Chiedi all'IA": a short explanation of a circled term.
    static func explain(term: String, context: String?) async throws(ExplanationError) -> WordExplanation {
        try GeminiExplainer.explanation(fromModelText: await ask(GeminiExplainer.prompt(term: term, context: context),
                                                                 for: .ask))
    }

    /// Sends a tiny message to check a key; throws why it doesn't work.
    static func test(_ provider: AIProvider, apiKey: String) async throws(ExplanationError) {
        try await firstAnswer(provider) { model in
            let text = try await AIRequests.answerText(send(AIRequests.testRequest(provider: provider, apiKey: apiKey,
                                                                                   model: model), provider, model),
                                                       provider: provider)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ExplanationError.badResponse }
        }
    }

    /// Tries the provider's models in order, the chosen one first.
    private static func firstAnswer<T>(_ provider: AIProvider,
                                       _ ask: (String) async throws -> T) async throws(ExplanationError) -> T {
        var lastError = ExplanationError.unavailable
        for model in provider.models(preferred: UserDefaults.standard.string(forKey: modelKey(provider))) {
            do {
                return try await ask(model)
            } catch {
                let failure = error as? ExplanationError ?? .unavailable
                guard GeminiExplainer.shouldTryNextModel(after: failure), !Task.isCancelled else { throw failure }
                lastError = failure
            }
        }
        throw lastError
    }

    private static func send(_ request: URLRequest, _ provider: AIProvider,
                             _ model: String) async throws(ExplanationError) -> Data {
        let start = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            log(start, "\(model) URLError \(error.code.rawValue) \(error.localizedDescription)")
            throw GeminiExplainer.error(for: error)
        } catch {
            log(start, "\(model) errore \(error)")
            throw .unavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        log(start, "\(model) HTTP \(status) \(String(decoding: data.prefix(600), as: UTF8.self))")
        guard status == 200 else { throw AIRequests.error(status: status, body: data, provider: provider) }
        return data
    }

    /// Duration and outcome of each request (never the key), in Documents/diagnostica-ia.txt. Debug builds only.
    private static func log(_ start: Date, _ message: String) {
        #if DEBUG
        let line = "\(Date().formatted(date: .numeric, time: .standard)) \(String(format: "%.1f", Date().timeIntervalSince(start)))s \(message)\n"
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostica-ia.txt") else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
        #endif
    }
}
