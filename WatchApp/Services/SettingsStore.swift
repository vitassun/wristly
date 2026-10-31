import Foundation
import Security
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var endpoint: String
    @Published var token: String
    private static let account = "wristly.private-access"

    init() {
        endpoint = UserDefaults.standard.string(forKey: "backendURL") ?? ""
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: Self.account, kSecAttrAccount as String: "owner",
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        token = status == errSecSuccess ? String(data: item as? Data ?? Data(), encoding: .utf8) ?? "" : ""
    }

    func connection() throws -> Connection {
        let text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text), parts.scheme == "https", parts.host != nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let url = parts.url else {
            throw ClientError.message("请输入 HTTPS 后端地址，例如 https://wristly.example.workers.dev")
        }
        guard token.isEmpty || (32...256).contains(token.utf8.count) else { throw ClientError.message("令牌可留空；填写时需为 32–256 字节") }
        return Connection(baseURL: url, token: token)
    }

    func save() throws {
        _ = try connection()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: Self.account, kSecAttrAccount as String: "owner"]
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ClientError.message("无法清除旧令牌") }
            UserDefaults.standard.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "backendURL")
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var add = query
            attributes.forEach { add[$0.key] = $0.value }
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw ClientError.message("无法保存到钥匙串") }
        } else if update != errSecSuccess { throw ClientError.message("无法更新钥匙串") }
        UserDefaults.standard.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "backendURL")
    }
}
