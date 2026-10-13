import Foundation
import Security
import SongServices

@MainActor
final class ModelSettings: ObservableObject {
    @Published private(set) var preferences: ModelPreferences
    private let defaults: UserDefaults
    private let storageKey = "languageModelPreferences.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(ModelPreferences.self, from: $0) } ?? ModelPreferences()
    }
    func save(_ preferences: ModelPreferences, newKey: String) throws {
        if preferences.api.enabled {
            _ = try preferences.api.endpoint()
            guard !preferences.api.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProviderError.unavailable("APIのモデル名を入力してください。")
            }
        }
        if !newKey.isEmpty { try ModelKeychain.save(newKey, account: preferences.api.baseURL) }
        defaults.set(try JSONEncoder().encode(preferences), forKey: storageKey)
        self.preferences = preferences
    }
    func clients() async -> [ModelClient] {
        let config = preferences
        let key = config.api.enabled ? (try? ModelKeychain.read(account: config.api.baseURL)) ?? "" : ""
        return await ModelDiscovery.clients(preferences: config, apiKey: key)
    }
}

/// Keys are tied to an endpoint and this app's identity. They never enter a song or UserDefaults.
enum ModelKeychain {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "org.syllablesfinder") + ".model-api" }
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func read(account: String) throws -> String {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = value as? Data, let key = String(data: data, encoding: .utf8) else {
            throw ProviderError.unavailable("キーチェーンからAPIキーを読み出せませんでした（\(status)）。")
        }
        return key
    }
    static func save(_ key: String, account: String) throws {
        let query = query(account)
        let values: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ProviderError.unavailable("APIキーをキーチェーンに保存できませんでした（\(status)）。") }
    }
}
