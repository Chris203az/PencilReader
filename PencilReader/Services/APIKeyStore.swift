import Foundation
import Observation
import ReaderCore
import Security

/// The Google AI Studio key, kept in the Keychain (only on this device).
@MainActor
@Observable
final class APIKeyStore {
    static let shared = APIKeyStore()

    private(set) var googleKey: String?
    var hasGoogleKey: Bool { googleKey != nil }

    private static let service = "com.christianrauso.PencilReader.ai"
    private static let account = "google-ai-studio"

    private init() {
        googleKey = Self.read()
    }

    @discardableResult
    func saveGoogleKey(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        SecItemDelete(Self.query as CFDictionary)
        var item = Self.query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return false }
        googleKey = key
        return true
    }

    func deleteGoogleKey() {
        SecItemDelete(Self.query as CFDictionary)
        googleKey = nil
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }
}

/// Asks Gemini for a short explanation of a circled term.
enum WordExplainer {
    static func explain(term: String, context: String?, apiKey: String) async throws(ExplanationError) -> WordExplanation {
        try await firstAnswer { model in
            try await GeminiExplainer.parse(send(GeminiExplainer.request(term: term, context: context,
                                                                         apiKey: apiKey, model: model)))
        }
    }

    /// Sends a tiny message to check the key; throws why it doesn't work.
    static func test(apiKey: String) async throws(ExplanationError) {
        try await firstAnswer { model in
            try await GeminiExplainer.parseTest(send(GeminiExplainer.testRequest(apiKey: apiKey, model: model)))
        }
    }

    /// Tries the models in order, moving on when one is overloaded, too slow or out of quota.
    private static func firstAnswer<T>(_ ask: (String) async throws -> T) async throws(ExplanationError) -> T {
        var lastError = ExplanationError.unavailable
        for model in GeminiExplainer.models {
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

    private static func send(_ request: URLRequest) async throws(ExplanationError) -> Data {
        let start = Date()
        let model = request.url?.lastPathComponent ?? ""
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
        guard status == 200 else { throw GeminiExplainer.error(status: status, body: data) }
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
