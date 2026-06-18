import Foundation

/// Persists a verified PIN per FWPlayer device so the user only enters it once.
enum PairedPINStore {
    private static let prefix = "pairedPIN."

    static func pin(for playerID: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + playerID)
    }

    static func save(_ pin: String, for playerID: String) {
        UserDefaults.standard.set(pin, forKey: prefix + playerID)
    }

    static func remove(for playerID: String) {
        UserDefaults.standard.removeObject(forKey: prefix + playerID)
    }

    static func isPaired(_ playerID: String) -> Bool {
        pin(for: playerID) != nil
    }
}
