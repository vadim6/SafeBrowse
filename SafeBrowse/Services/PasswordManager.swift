import Foundation
import Security
import CryptoKit

/// Stores and verifies the parental-control password using Keychain + SHA-256.
final class PasswordManager {

    private let service = "com.safebrowse.app"
    private let account = "pause-password"

    var isPasswordSet: Bool {
        loadHash() != nil
    }

    func setPassword(_ password: String) {
        let hash = sha256(password)
        saveHash(hash)
    }

    func verifyPassword(_ password: String) -> Bool {
        guard let stored = loadHash() else { return false }
        return sha256(password) == stored
    }

    func clearPassword() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Helpers

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func saveHash(_ hash: String) {
        let data = Data(hash.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadHash() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let hash = String(data: data, encoding: .utf8)
        else { return nil }
        return hash
    }
}
