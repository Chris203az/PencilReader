import Foundation
import Observation
import ReaderCore
import Security

/// One API key per AI provider, kept in the Keychain (only on this device).
@MainActor
@Observable
final class APIKeyStore {
    static let shared = APIKeyStore()

    private(set) var keys: [AIProvider: String] = [:]

    func key(for provider: AIProvider) -> String? { keys[provider] }
    func hasKey(for provider: AIProvider) -> Bool { keys[provider] != nil }

    private static let service = "com.christianrauso.PencilReader.ai"

    private init() {
        for provider in AIProvider.allCases {
            keys[provider] = Self.read(provider)
        }
    }

    @discardableResult
    func save(_ key: String, for provider: AIProvider) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        SecItemDelete(Self.query(provider) as CFDictionary)
        var item = Self.query(provider)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return false }
        keys[provider] = key
        return true
    }

    func delete(for provider: AIProvider) {
        SecItemDelete(Self.query(provider) as CFDictionary)
        keys[provider] = nil
    }

    /// The Google account name predates the other providers: kept so the saved key still works.
    private static func account(_ provider: AIProvider) -> String {
        switch provider {
        case .google: "google-ai-studio"
        case .deepseek: "deepseek"
        }
    }

    private static func query(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account(provider)]
    }

    private static func read(_ provider: AIProvider) -> String? {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }
}
