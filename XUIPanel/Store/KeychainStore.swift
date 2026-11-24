import Foundation
import Security

/// 极薄的钥匙串封装：每个服务器档案用 `id` 作为账号名，
/// 存 `password` 与 `username` 两条记录，永不落到 UserDefaults / JSON 文件里。
enum KeychainStore {
    static let service = "com.lin.xui.panel.credentials"

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else {
            delete(account: account)
            return true
        }
        let data = Data(value.utf8)
        var base = query(account: account)
        SecItemDelete(base as CFDictionary)
        base[kSecValueData as String] = data
        base[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(base as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func get(account: String) -> String? {
        var base = query(account: account)
        base[kSecReturnData as String] = true
        base[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(base as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let base = query(account: account)
        SecItemDelete(base as CFDictionary)
    }

    static func passwordAccount(for id: UUID) -> String {
        "\(id.uuidString).password"
    }

    static func usernameAccount(for id: UUID) -> String {
        "\(id.uuidString).username"
    }
}
