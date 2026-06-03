import Foundation
import LevelItShared

/// 调用阿里云 ECS 中转代理，让后台大模型估算每日总能量消耗。
enum DailyEnergyEstimateService {
    private static let endpoint = "http://39.105.196.84/api/estimate-daily-energy"
    private static let timeoutSeconds: TimeInterval = 45

    struct EstimateResult: Decodable {
        let estimatedDailyCalories: Int
        let summary: String
        let confidence: Double?
    }

    private struct EstimateRequest: Encodable {
        let gender: String
        let age: Int
        let heightCM: Int
        let weightKG: Double
        let activityLevel: String
        let activityDescription: String
        let bmr: Int
        let formulaTDEE: Int
    }

    enum EstimateError: LocalizedError {
        case invalidEndpoint
        case networkError(String)
        case serverError(String)
        case timeout
        case invalidCalories

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "估算接口地址无效"
            case .networkError(let message): return "网络错误: \(message)"
            case .serverError(let message): return "服务错误: \(message)"
            case .timeout: return "估算超时，请稍后重试"
            case .invalidCalories: return "后台返回的日常消耗数值不合理"
            }
        }
    }

    static func estimate(profile: UserProfile) async throws -> EstimateResult {
        guard let url = URL(string: endpoint) else {
            throw EstimateError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutSeconds
        request.httpBody = try JSONEncoder().encode(EstimateRequest(
            gender: profile.gender.rawValue,
            age: profile.age,
            heightCM: profile.heightCM,
            weightKG: profile.weightKG,
            activityLevel: profile.activityLevel.rawValue,
            activityDescription: profile.activityLevel.description,
            bmr: profile.bmr,
            formulaTDEE: profile.formulaTDEE
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw EstimateError.timeout
            }
            throw EstimateError.networkError("[\(error.code.rawValue)] \(error.localizedDescription)")
        } catch {
            throw EstimateError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EstimateError.serverError("Invalid response")
        }

        if httpResponse.statusCode == 404 {
            throw EstimateError.serverError("阿里云 ECS 尚未部署 /api/estimate-daily-energy 新接口，请先发布 levelit-proxy 后重试")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw EstimateError.serverError("HTTP \(httpResponse.statusCode): \(responseBody)")
        }

        let result = try JSONDecoder().decode(EstimateResult.self, from: data)
        guard AppConstants.ProfileDefaults.minDailyEnergyEstimate...AppConstants.ProfileDefaults.maxDailyEnergyEstimate ~= result.estimatedDailyCalories else {
            throw EstimateError.invalidCalories
        }
        return result
    }
}
