import Foundation
import Security

/// Mantiene un identificativo univoco e persistente del dispositivo nel Keychain iOS (`ThisDeviceOnly`).
/// Sopravvive ad aggiornamenti App Store, disinstallazioni/reinstallazioni e passaggi Xcode <-> App Store,
/// ma non viene trasferito su altri iPhone tramite backup iCloud.
final class DeviceIdentityManager: @unchecked Sendable {
    static let shared = DeviceIdentityManager()

    private let lock = NSLock()
    private let service: String
    private let account: String
    private let defaults: UserDefaults
    private let fallbackDefaultsKey: String
    private var cachedDeviceID: String?

    internal init(
        service: String = "com.toreroclub.inorario.device-identity",
        account: String = "persistent_device_id_v1",
        defaults: UserDefaults = .standard,
        fallbackDefaultsKey: String = "persistent_device_id_fallback_v1"
    ) {
        self.service = service
        self.account = account
        self.defaults = defaults
        self.fallbackDefaultsKey = fallbackDefaultsKey
    }

    var deviceID: String {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedDeviceID, !cached.isEmpty {
            return cached
        }

        if let keychainValue = readFromKeychain(), !keychainValue.isEmpty {
            if defaults.string(forKey: fallbackDefaultsKey) != keychainValue {
                defaults.set(keychainValue, forKey: fallbackDefaultsKey)
            }
            cachedDeviceID = keychainValue
            return keychainValue
        }

        if let fallbackValue = defaults.string(forKey: fallbackDefaultsKey), !fallbackValue.isEmpty {
            _ = saveToKeychain(fallbackValue)
            cachedDeviceID = fallbackValue
            return fallbackValue
        }

        let newID = UUID().uuidString.lowercased()
        _ = saveToKeychain(newID)
        defaults.set(newID, forKey: fallbackDefaultsKey)
        cachedDeviceID = newID
        return newID
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func readFromKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else {
            return nil
        }
        return str
    }

    @discardableResult
    private func saveToKeychain(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }
        if addStatus == errSecDuplicateItem {
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributesToUpdate as CFDictionary)
            return updateStatus == errSecSuccess
        }
        return false
    }
}
