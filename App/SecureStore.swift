import Foundation
import Security
import CryptoKit
import BahaCore

struct SecureStore {
    private let service = "com.kittenello.bahavpn.storage"
    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profiles-v1.aes")
    }

    func read() throws -> ClientState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ClientState() }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: fileURL))
        let clear = try AES.GCM.open(sealed, using: key(create: false))
        return try JSONDecoder().decode(ClientState.self, from: clear)
    }

    func write(_ state: ClientState) throws {
        let data = try JSONEncoder().encode(state)
        let sealed = try AES.GCM.seal(data, using: key(create: true))
        guard let combined = sealed.combined else { throw ClientError.invalid("ошибка шифрования") }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try combined.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func key(create: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "aes-key"]
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound, create else { throw ClientError.invalid("хранилище недоступно: \(status)") }
        let key = SymmetricKey(size: .bits256)
        var insert = query
        insert[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let result = SecItemAdd(insert as CFDictionary, nil)
        guard result == errSecSuccess else { throw ClientError.invalid("не удалось сохранить ключ: \(result)") }
        return key
    }
}
