import Foundation
import SwiftData
import LevelItShared

/// 同步本地 PKChallenge 与服务端的 CRUD 操作。
/// 所有方法都是 async throws。网络不可用时抛 PKSyncError，调用方决定是否静默忽略。
enum PKSyncService {
    private static let baseURL = "http://39.105.196.84/api/pk"
    private static let timeout: TimeInterval = 20

    enum PKSyncError: LocalizedError {
        case notLoggedIn
        case serverError(Int, String)
        case networkError(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:            return "请先登录账号"
            case .serverError(let c, let m): return "服务器错误 \(c): \(m)"
            case .networkError(let m):    return "网络错误：\(m)"
            case .invalidResponse:        return "响应格式异常"
            }
        }
    }

    // MARK: - Codable DTOs

    private struct ChallengeDTO: Codable {
        let id: String
        let inviteCode: String
        let type: String
        let status: String
        let title: String
        let challengerId: String
        let challengerName: String
        let challengerCode: String
        let challengerProgress: Int
        let opponentId: String?
        let opponentName: String?
        let opponentCode: String?
        let opponentProgress: Int
        let targetCalories: Int
        let durationDays: Int
        let expiresAt: String
        let createdAt: String
        let acceptedAt: String?
        let completedAt: String?
        let note: String?
    }

    private struct CreateRequest: Encodable {
        let type: String
        let title: String
        let challengerName: String
        let challengerCode: String
        let opponentName: String?
        let targetCalories: Int
        let durationDays: Int
        let note: String?
        let expiresInHours: Double
    }

    private struct UpdateRequest: Encodable {
        let title: String?
        let targetCalories: Int?
        let durationDays: Int?
        let note: String?
        let expiresAt: String?
        let status: String?
    }

    private struct ClaimRequest: Encodable {
        let inviteCode: String
        let opponentName: String
        let opponentCode: String
    }

    private struct ProgressRequest: Encodable {
        let progress: Int
    }

    private struct DeviceTokenRequest: Encodable {
        let deviceToken: String
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    // MARK: - Token

    private static func authToken() throws -> String {
        guard let token = AuthSessionStore.current?.token, !token.isEmpty else {
            throw PKSyncError.notLoggedIn
        }
        return token
    }

    // MARK: - Networking helpers

    private static func request<T: Decodable>(
        path: String,
        method: String,
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw PKSyncError.invalidResponse }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(try authToken())", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw PKSyncError.invalidResponse }
        if http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? "unknown"
            throw PKSyncError.serverError(http.statusCode, msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Public API

    /// 将本地新建的挑战上传服务端，返回服务端 id。
    static func createChallenge(_ challenge: PKChallenge) async throws -> String {
        let expiresInHours = challenge.expiresAt.timeIntervalSince(Date()) / 3600
        let body = CreateRequest(
            type: challenge.type.rawValue,
            title: challenge.title,
            challengerName: challenge.challengerName,
            challengerCode: challenge.challengerCode,
            opponentName: challenge.opponentName,
            targetCalories: challenge.targetCalories,
            durationDays: challenge.durationDays,
            note: challenge.note,
            expiresInHours: max(1, expiresInHours)
        )
        let dto: ChallengeDTO = try await request(path: "/challenges", method: "POST", body: body)
        return dto.id
    }

    /// 用邀请码认领挑战，返回已填充服务端数据的本地 PKChallenge（调用方负责 insert 到 modelContext）。
    static func claimChallenge(
        inviteCode: String,
        opponentName: String,
        opponentCode: String
    ) async throws -> PKChallenge {
        let body = ClaimRequest(inviteCode: inviteCode, opponentName: opponentName, opponentCode: opponentCode)
        let dto: ChallengeDTO = try await request(path: "/claim", method: "POST", body: body)
        let type = PKChallengeType(rawValue: dto.type) ?? .burnTarget
        let challenge = PKChallenge(
            id: UUID().uuidString,
            type: type,
            title: dto.title,
            challengerName: dto.challengerName,
            challengerCode: dto.challengerCode,
            opponentName: opponentName,
            targetCalories: dto.targetCalories,
            durationDays: dto.durationDays,
            status: .accepted,
            note: dto.note,
            isChallenger: false,
            serverId: dto.id
        )
        if let acceptedStr = dto.acceptedAt {
            challenge.acceptedAt = ISO8601DateFormatter().date(from: acceptedStr)
        }
        return challenge
    }

    /// 更新服务端挑战字段（仅 invited 状态有效）。
    static func updateChallenge(_ challenge: PKChallenge) async throws {
        guard let serverId = challenge.serverId else { return }
        let iso = ISO8601DateFormatter()
        let body = UpdateRequest(
            title: challenge.title,
            targetCalories: challenge.targetCalories,
            durationDays: challenge.durationDays,
            note: challenge.note,
            expiresAt: iso.string(from: challenge.expiresAt),
            status: nil
        )
        let _: ChallengeDTO = try await request(path: "/challenges/\(serverId)", method: "PUT", body: body)
    }

    /// 撤回挑战（只能撤回 invited 状态）。
    static func cancelChallenge(_ challenge: PKChallenge) async throws {
        guard let serverId = challenge.serverId else { return }
        let body = UpdateRequest(title: nil, targetCalories: nil, durationDays: nil, note: nil, expiresAt: nil, status: "cancelled")
        let _: ChallengeDTO = try await request(path: "/challenges/\(serverId)", method: "PUT", body: body)
    }

    /// 删除服务端挑战记录（终态才允许删除）。
    static func deleteChallenge(_ challenge: PKChallenge) async throws {
        guard let serverId = challenge.serverId else { return }
        struct OKResponse: Decodable { let ok: Bool }
        let _: OKResponse = try await request(path: "/challenges/\(serverId)", method: "DELETE")
    }

    /// 推送我方进度到服务端，返回更新后对手进度。
    static func pushProgress(_ challenge: PKChallenge) async throws -> Int {
        guard let serverId = challenge.serverId else { return challenge.opponentProgress }
        let dto: ChallengeDTO = try await request(
            path: "/challenges/\(serverId)/progress",
            method: "PUT",
            body: ProgressRequest(progress: challenge.myProgress)
        )
        return challenge.isChallenger ? dto.opponentProgress : dto.challengerProgress
    }

    /// 拉取服务端最新状态（单个挑战），内部同步用。
    private static func fetchChallenge(_ challenge: PKChallenge) async throws -> ChallengeDTO? {
        guard let serverId = challenge.serverId else { return nil }
        return try await request(path: "/challenges/\(serverId)", method: "GET")
    }

    /// 拉取我参与的全部挑战（内部同步用）。
    private static func fetchAllChallenges() async throws -> [ChallengeDTO] {
        return try await request(path: "/challenges", method: "GET")
    }

    /// 注册 APNs device token，绑定到指定挑战。
    static func registerDeviceToken(_ token: String, for challenge: PKChallenge) async throws {
        guard let serverId = challenge.serverId else { return }
        struct OKResponse: Decodable { let ok: Bool }
        let _: OKResponse = try await request(
            path: "/challenges/\(serverId)/device-token",
            method: "PUT",
            body: DeviceTokenRequest(deviceToken: token)
        )
    }

    // MARK: - DTO → local model mapping

    /// 将服务端 DTO 的对手进度 / 状态同步回本地 SwiftData 对象。
    private static func applyDTO(_ dto: ChallengeDTO, to challenge: PKChallenge, myUserId: String) {
        let opponentProgress = challenge.isChallenger ? dto.opponentProgress : dto.challengerProgress
        challenge.opponentProgress = opponentProgress

        if let serverStatus = PKChallengeStatus(rawValue: dto.status) {
            challenge.status = serverStatus
        }
        if let accepted = dto.acceptedAt {
            challenge.acceptedAt = ISO8601DateFormatter().date(from: accepted)
        }
        if let completed = dto.completedAt {
            challenge.completedAt = ISO8601DateFormatter().date(from: completed)
        }
        if challenge.isChallenger, let opponentName = dto.opponentName {
            challenge.opponentName = opponentName
        }
    }
}
