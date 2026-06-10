import Foundation
import Security

public struct AuthSession: Codable, Sendable, Equatable {
    public var token: String
    public var userId: String
    public var identifier: String
    public var createdAt: Date

    public init(
        token: String,
        userId: String,
        identifier: String,
        createdAt: Date = Date()
    ) {
        self.token = token
        self.userId = userId
        self.identifier = identifier
        self.createdAt = createdAt
    }
}

/// 会话凭据存储。
///
/// 凭据(含 30 天 JWT)保存在 **Keychain**,而非 UserDefaults——后者会进入
/// 设备备份、且越狱/文件级访问可明文读取。Keychain 使用
/// `AfterFirstUnlockThisDeviceOnly`:后台可读,但不随 iCloud/iTunes 备份迁移到其它设备。
public enum AuthSessionStore {
    private static let service = "com.levelit.authsession"
    private static let account = "authSession_v1"
    /// 旧版本把会话明文存在 UserDefaults,这里用于一次性迁移
    private static let legacyDefaultsKey = "authSession_v1"

    public static var current: AuthSession? {
        // 先尝试 Keychain
        if let data = keychainRead(),
           let session = try? JSONDecoder().decode(AuthSession.self, from: data),
           !session.token.isEmpty {
            return session
        }
        // 迁移:老用户的会话还在 UserDefaults 里,搬到 Keychain 后清掉
        if let legacy = migrateFromDefaults() {
            return legacy
        }
        return nil
    }

    public static var isAuthenticated: Bool {
        current != nil
    }

    public static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        keychainWrite(data)
    }

    public static func clear() {
        keychainDelete()
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    // MARK: - 迁移

    private static func migrateFromDefaults() -> AuthSession? {
        guard let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data),
              !session.token.isEmpty
        else { return nil }
        keychainWrite(data)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        return session
    }

    // MARK: - Keychain 原语

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func keychainRead() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func keychainWrite(_ data: Data) {
        // upsert:先删后加,避免 duplicate item
        SecItemDelete(baseQuery() as CFDictionary)
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func keychainDelete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
