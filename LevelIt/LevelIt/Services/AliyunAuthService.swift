import Foundation
import LevelItShared

enum AliyunAuthService {
    private static let baseURL = APIConfig.apiBase
    private static let timeoutSeconds: TimeInterval = 30

    struct AuthResult: Decodable {
        let token: String
        let userId: String
        let username: String?
        let profile: UserProfile
    }

    private struct RegisterRequest: Encodable {
        let identifier: String
        let password: String
        let profile: UserProfile
    }

    private struct LoginRequest: Encodable {
        let identifier: String
        let password: String
    }

    private struct ProfileUpdateRequest: Encodable {
        let profile: UserProfile
    }

    private struct CurrentUserResponse: Decodable {
        let userId: String
        let identifier: String?
        let profile: UserProfile
    }

    enum AuthError: LocalizedError {
        case invalidEndpoint
        case missingSession
        case networkError(String)
        case serverError(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "认证接口地址无效"
            case .missingSession: return "登录状态已失效，请重新登录"
            case .networkError(let message): return "网络错误: \(message)"
            case .serverError(let message): return "服务错误: \(message)"
            case .timeout: return "连接服务器超时，请稍后重试"
            }
        }
    }

    static func register(
        identifier: String,
        password: String,
        profile: UserProfile
    ) async throws -> AuthResult {
        try await send(
            path: "/auth/register",
            method: "POST",
            body: RegisterRequest(
                identifier: normalized(identifier),
                password: password,
                profile: profile
            )
        )
    }

    static func login(identifier: String, password: String) async throws -> AuthResult {
        try await send(
            path: "/auth/login",
            method: "POST",
            body: LoginRequest(identifier: normalized(identifier), password: password)
        )
    }

    static func fetchCurrentUser() async throws -> UserProfile {
        let response: CurrentUserResponse = try await send(
            path: "/auth/me",
            method: "GET",
            body: Optional<String>.none,
            token: try currentToken()
        )
        return response.profile
    }

    static func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        let response: CurrentUserResponse = try await send(
            path: "/auth/profile",
            method: "PUT",
            body: ProfileUpdateRequest(profile: profile),
            token: try currentToken()
        )
        return response.profile
    }

    static func apply(_ result: AuthResult, identifier: String) {
        AuthSessionStore.save(AuthSession(
            token: result.token,
            userId: result.userId,
            identifier: normalized(identifier),
            username: result.username
        ))
        UserProfileStore.save(result.profile)
    }

    /// 更新本地会话里的用户名（改名成功后调用）
    static func updateStoredUsername(_ username: String) {
        guard var session = AuthSessionStore.current else { return }
        session.username = username
        AuthSessionStore.save(session)
    }

    static func logout() {
        AuthSessionStore.clear()
        UserProfileStore.clear()
    }

    /// 删除账号：请求服务端删除用户及其 PK/好友数据，成功后清空本地会话与档案。
    /// 调用方负责清理本地 SwiftData（挑战等）并跳回登录页。
    static func deleteAccount() async throws {
        let _: DeleteResponse = try await send(
            path: "/auth/account",
            method: "DELETE",
            body: Optional<String>.none,
            token: try currentToken()
        )
        logout()
    }

    private struct DeleteResponse: Decodable { let ok: Bool }

    private static func currentToken() throws -> String {
        guard let token = AuthSessionStore.current?.token else {
            throw AuthError.missingSession
        }
        return token
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody,
        token: String? = nil
    ) async throws -> ResponseBody {
        guard let url = URL(string: baseURL + path) else {
            throw AuthError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if !(body is Optional<String>) {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw AuthError.timeout
            }
            throw AuthError.networkError("[\(error.code.rawValue)] \(error.localizedDescription)")
        } catch {
            throw AuthError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.serverError("Invalid response")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.serverError("HTTP \(httpResponse.statusCode): \(responseBody)")
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }
}
