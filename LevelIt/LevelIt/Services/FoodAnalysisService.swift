import UIKit
import LevelItShared

/// 调用阿里云 ECS 中转代理 → Kimi-K2.5 Vision API 识别食物并估算热量
enum FoodAnalysisService {
    private static let endpoint = "http://39.105.196.84/api/analyze"
    private static let maxImageDimension: CGFloat = 512
    private static let jpegQuality: CGFloat = 0.7
    private static let timeoutSeconds: TimeInterval = 60

    struct AnalysisResult: Decodable {
        var foodName: String
        var foodEmoji: String
        var estimatedCalories: Int
        let confidence: Double
        let warning: String?
    }

    enum AnalysisError: LocalizedError {
        case imageCompressionFailed
        case networkError(String)
        case serverError(String)
        case notFood
        case timeout

        var errorDescription: String? {
            switch self {
            case .imageCompressionFailed: return "图片压缩失败"
            case .networkError(let msg): return "网络错误: \(msg)"
            case .serverError(let msg): return "服务错误: \(msg)"
            case .notFood: return "看起来不是食物或饮料"
            case .timeout: return "分析超时，请重试"
            }
        }
    }

    /// 分析食物照片，返回识别结果
    static func analyze(image: UIImage) async throws -> AnalysisResult {
        // 1. 压缩图片
        guard let base64 = compressAndEncode(image) else {
            throw AnalysisError.imageCompressionFailed
        }

        // 2. 构造请求
        guard let url = URL(string: endpoint) else {
            throw AnalysisError.serverError("Invalid endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // #2：AI 端点需鉴权，附带登录 token，防止接口被匿名刷量
        if let token = AuthSessionStore.current?.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = timeoutSeconds

        let body = try JSONSerialization.data(withJSONObject: ["image": base64])
        request.httpBody = body

        // 3. 发送请求
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw AnalysisError.timeout
            }
            throw AnalysisError.networkError("[\(error.code.rawValue)] \(error.localizedDescription)")
        } catch {
            throw AnalysisError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.serverError("Invalid response")
        }

        if httpResponse.statusCode == 401 {
            throw AnalysisError.serverError("登录状态已失效，请重新登录后再试")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.serverError("HTTP \(httpResponse.statusCode): \(responseBody)")
        }

        // 4. 解析结果 + 校验
        var result = try JSONDecoder().decode(AnalysisResult.self, from: data)

        if result.confidence < 0.3 {
            throw AnalysisError.notFood
        }

        // 热量边界校验：钳位到合理范围
        result.estimatedCalories = CalorieCalculator.clampedCalories(result.estimatedCalories)

        // foodName 兜底
        if result.foodName.trimmingCharacters(in: .whitespaces).isEmpty {
            result.foodName = "未知食物"
        }

        return result
    }

    /// 将图片缩放到 maxImageDimension 并转为 JPEG Base64
    private static func compressAndEncode(_ image: UIImage) -> String? {
        let resized = resizeImage(image, maxDimension: maxImageDimension)
        guard let jpegData = resized.jpegData(compressionQuality: jpegQuality) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    private static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }

        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
