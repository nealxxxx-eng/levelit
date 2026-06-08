import Foundation

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

public enum AuthSessionStore {
    private static let key = "authSession_v1"

    public static var current: AuthSession? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data),
              !session.token.isEmpty
        else { return nil }
        return session
    }

    public static var isAuthenticated: Bool {
        current != nil
    }

    public static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
