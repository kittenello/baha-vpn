import Foundation
import UIKit
import Security
import CryptoKit
import BahaCore

/// A persistent app/device seed; not an Apple UDID, IMEI, advertising ID or a serial number.
enum DeviceIdentity {
    static func metadata(for url: URL) throws -> SubscriptionDevice {
        let seed = try loadSeed()
        let provider = (url.host ?? "").lowercased()
        let digest = SHA256.hash(data: seed + Data("baha-vpn:\(provider)".utf8))
        let hwid = digest.map { String(format: "%02x", $0) }.joined()
        return SubscriptionDevice(hwid: hwid, os: "iOS", version: UIDevice.current.systemVersion, model: UIDevice.current.model)
    }

    private static func loadSeed() throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "com.kittenello.bahavpn.device",
                                   kSecAttrAccount as String: "hwid-seed"]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 { return data }
        guard status == errSecItemNotFound else { throw ClientError.invalid("идентификатор устройства недоступен: \(status)") }
        var seed = Data(count: 32)
        let result = seed.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard result == errSecSuccess else { throw ClientError.invalid("не удалось создать идентификатор устройства") }
        var insert = query
        insert[kSecValueData as String] = seed
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw ClientError.invalid("не удалось сохранить идентификатор устройства: \(added)") }
        return seed
    }
}
