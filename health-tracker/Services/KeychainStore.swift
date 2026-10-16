//
//  KeychainStore.swift
//  health-tracker
//
//  Stores small secrets (the Anthropic API key) in the Keychain rather than UserDefaults.
//

import Foundation
import Security

struct KeychainStore {
    let service: String

    static let anthropicAPIKey = KeychainStore(service: "luisbenavides.health-tracker.anthropic-api-key")

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves `value`, replacing any existing one. An empty value deletes it.
    @discardableResult
    func save(_ value: String) -> Bool {
        delete()
        guard !value.isEmpty else { return true }
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        // Available after the first unlock so it never syncs or leaves the device.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
