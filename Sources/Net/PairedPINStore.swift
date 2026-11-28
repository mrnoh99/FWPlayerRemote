import Foundation
import Security

/// Persists a verified PIN per FWPlayer device so the user only enters it once.
/// PINs live in the Keychain; one saved by an older version in UserDefaults moves
/// there the first time it is read. If the Keychain refuses a write, the PIN stays in
/// UserDefaults so pairing still works.
enum PairedPINStore {
    private static let legacyPrefix = "pairedPIN."
    private static let service = "com.fwplayer.remote.pairedPIN"

    static func pin(for playerID: String) -> String? {
        if let pin = keychainPIN(for: playerID) { return pin }
        guard let legacy = UserDefaults.standard.string(forKey: legacyPrefix + playerID) else { return nil }
        if saveToKeychain(legacy, for: playerID) {
            UserDefaults.standard.removeObject(forKey: legacyPrefix + playerID)
        }
        return legacy
    }

    static func save(_ pin: String, for playerID: String) {
        if saveToKeychain(pin, for: playerID) {
            UserDefaults.standard.removeObject(forKey: legacyPrefix + playerID)
        } else {
            UserDefaults.standard.set(pin, forKey: legacyPrefix + playerID)
        }
    }

    static func remove(for playerID: String) {
        SecItemDelete(query(for: playerID) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: legacyPrefix + playerID)
    }

    static func isPaired(_ playerID: String) -> Bool {
        pin(for: playerID) != nil
    }

    // MARK: Keychain

    private static func query(for playerID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: playerID]
    }

    private static func keychainPIN(for playerID: String) -> String? {
        var request = query(for: playerID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToKeychain(_ pin: String, for playerID: String) -> Bool {
        let data = Data(pin.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query(for: playerID) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query(for: playerID)
        item[kSecValueData as String] = data
        // Readable after the first unlock, so a reconnect in the background works; never synced.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
