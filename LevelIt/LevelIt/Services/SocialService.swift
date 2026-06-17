import Foundation
import LevelItShared

/// 社交后端客户端：用户名、搜索、好友、发榜广场、排行榜。
/// 与 PKSyncService 同源（同一后端、Bearer token），网络不可用时抛 SocialError。
enum SocialService {
    private static let base = APIConfig.apiBase
    private static let timeout: TimeInterval = 20

    enum SocialError: LocalizedError {
        case notLoggedIn
        case serverError(Int, String)
        case network(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:            return "请先登录账号"
            case .serverError(_, let m):  return m
            case .network(let m):         return "网络错误：\(m)"
            case .invalidResponse:        return "响应格式异常"
            }
        }
    }

    // MARK: - DTOs

    struct UserSummary: Codable, Identifiable, Hashable {
        let username: String
        let displayName: String
        var id: String { username }
    }

    struct FriendRequestItem: Codable, Identifiable, Hashable {
        let id: String
        let user: UserSummary
        let createdAt: String
    }

    struct FriendRequests: Codable {
        let incoming: [FriendRequestItem]
        let outgoing: [FriendRequestItem]
    }

    struct LeaderboardRow: Codable, Identifiable, Hashable {
        let rank: Int
        let username: String
        let displayName: String
        let wins: Int
        let burned: Int
        let completed: Int
        let isMe: Bool
        // id 用 rank+username 组合，避免多个未设 username 的用户（username 兜底成同值）id 冲突
        var id: String { "\(rank)|\(username)" }

        enum CodingKeys: String, CodingKey {
            case rank, username, displayName, wins, burned, completed, isMe
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
            // 后端对未设 username 的用户返回 username:null（getPublicUserMap: u.username || null）。
            // username 必须容错，否则任一无名用户都会让整个排行榜解码失败。
            let name = try c.decodeIfPresent(String.self, forKey: .displayName)
            let uname = try c.decodeIfPresent(String.self, forKey: .username)
            username = uname ?? name ?? "用户"
            displayName = name ?? uname ?? "用户"
            wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
            burned = try c.decodeIfPresent(Int.self, forKey: .burned) ?? 0
            completed = try c.decodeIfPresent(Int.self, forKey: .completed) ?? 0
            isMe = try c.decodeIfPresent(Bool.self, forKey: .isMe) ?? false
        }
    }

    /// 广场挑战条目（复用 PK 的公开字段子集）
    struct BoardChallenge: Codable, Identifiable, Hashable {
        let id: String
        let inviteCode: String
        let type: String
        let title: String
        let challengerName: String
        let challengerUsername: String?
        let targetCalories: Int
        let durationDays: Int
        let expiresAt: String
        let note: String?
        let myRole: String?

        var isMine: Bool { myRole == "challenger" }
    }

    private struct BoardResponse: Codable { let total: Int; let items: [BoardChallenge] }
    private struct LeaderboardResponse: Codable { let items: [LeaderboardRow] }
    private struct SearchResponse: Codable { let results: [UserSummary] }
    private struct FriendsResponse: Codable { let friends: [UserSummary] }
    private struct ErrorBody: Codable { let error: String }
    private struct StatusBody: Codable { let status: String? }

    // MARK: - Core request

    private static func token() throws -> String {
        guard let t = AuthSessionStore.current?.token, !t.isEmpty else { throw SocialError.notLoggedIn }
        return t
    }

    @discardableResult
    private static func request<T: Decodable>(
        _ path: String, method: String = "GET", body: (any Encodable)? = nil, decode: T.Type
    ) async throws -> T {
        guard let url = URL(string: base + path) else { throw SocialError.invalidResponse }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }

        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw SocialError.network(error.localizedDescription) }

        guard let http = resp as? HTTPURLResponse else { throw SocialError.invalidResponse }
        if http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "请求失败"
            throw SocialError.serverError(http.statusCode, msg)
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }

    struct EmptyResponse: Decodable {}

    // MARK: - Username

    struct PublicUserResponse: Decodable { let username: String? }

    static func setUsername(_ username: String) async throws {
        struct Body: Encodable { let username: String }
        let r: PublicUserResponse = try await request("/auth/username", method: "PUT",
                                                       body: Body(username: username), decode: PublicUserResponse.self)
        if let u = r.username { AliyunAuthService.updateStoredUsername(u) }
    }

    static func searchUsers(_ query: String) async throws -> [UserSummary] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let r: SearchResponse = try await request("/users/search?q=\(q)", decode: SearchResponse.self)
        return r.results
    }

    // MARK: - Friends

    static func sendFriendRequest(username: String) async throws {
        struct Body: Encodable { let username: String }
        let _: StatusBody = try await request("/friends/request", method: "POST",
                                              body: Body(username: username), decode: StatusBody.self)
    }

    static func friendRequests() async throws -> FriendRequests {
        try await request("/friends/requests", decode: FriendRequests.self)
    }

    static func acceptRequest(id: String) async throws {
        let _: StatusBody = try await request("/friends/requests/\(id)/accept", method: "POST", decode: StatusBody.self)
    }

    static func rejectRequest(id: String) async throws {
        let _: EmptyResponse = try await request("/friends/requests/\(id)/reject", method: "POST", decode: EmptyResponse.self)
    }

    static func friends() async throws -> [UserSummary] {
        let r: FriendsResponse = try await request("/friends", decode: FriendsResponse.self)
        return r.friends
    }

    static func removeFriend(username: String) async throws {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let _: EmptyResponse = try await request("/friends/\(enc)", method: "DELETE", decode: EmptyResponse.self)
    }

    // MARK: - Board & Leaderboard

    static func board(limit: Int = 30, offset: Int = 0) async throws -> [BoardChallenge] {
        let r: BoardResponse = try await request("/pk/board?limit=\(limit)&offset=\(offset)", decode: BoardResponse.self)
        return r.items
    }

    static func leaderboard(limit: Int = 30) async throws -> [LeaderboardRow] {
        let r: LeaderboardResponse = try await request("/leaderboard?limit=\(limit)", decode: LeaderboardResponse.self)
        return r.items
    }

    /// 接受定向好友挑战（PK 接口，路径在 /pk/ 下）
    static func acceptDirectedChallenge(serverId: String) async throws {
        let _: EmptyResponse = try await request("/pk/challenges/\(serverId)/accept", method: "PUT", decode: EmptyResponse.self)
    }
}

/// 类型擦除 Encodable，便于把任意 body 编码
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
