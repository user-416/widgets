import Foundation
import OSLog
import Security

enum Keychain {
    static let service = "io.github.user-416.widgets"

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    private static let logger = Logger(subsystem: "io.github.user-416.widgets", category: "Keychain")

    static func store(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecParam)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("SecItemAdd failed for key \(key, privacy: .public): \(addStatus)")
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            logger.error("SecItemUpdate failed for key \(key, privacy: .public): \(updateStatus)")
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    static func retrieve(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            logger.error("SecItemCopyMatching failed for key \(key, privacy: .public): \(status)")
            return nil
        }
    }

    static func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("SecItemDelete failed for key \(key, privacy: .public): \(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
