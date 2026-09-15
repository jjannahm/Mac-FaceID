import Foundation
import Security

enum LockPasswordStore {
    static let service = "com.jjannahm.FaceKey.lock-password"
    static let account = "local-user"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var hasPassword: Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = false
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func save(_ password: String) throws {
        guard !password.isEmpty else { throw StoreError.empty }
        let data = Data(password.utf8)
        var update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StoreError.status(status) }
        update.merge(baseQuery) { current, _ in current }
        update[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(update as CFDictionary, nil)
        guard added == errSecSuccess else { throw StoreError.status(added) }
    }

    static func load() throws -> String {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw StoreError.status(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { throw StoreError.unreadable }
        return value
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    enum StoreError: LocalizedError {
        case empty, unreadable, status(OSStatus)
        var errorDescription: String? {
            switch self {
            case .empty: return "The password cannot be empty."
            case .unreadable: return "The saved password could not be read."
            case .status(let status):
                return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
            }
        }
    }
}
