import Foundation

/// 后端地址统一配置。
///
/// 切换到 HTTPS 时只需把 `scheme` 改为 "https"、`host` 改为你的域名，
/// 全 App 的网络层（认证 / PK / 社交 / AI 分析）一处生效；
/// 同时记得移除 Info.plist 里的 ATS 明文例外。
public enum APIConfig {
    /// 传输协议：上线 HTTPS 后改为 "https"
    public static let scheme = "http"
    /// 服务器主机：上线后改为你的域名（如 "api.levelit.app"）
    public static let host = "39.105.196.84"

    /// 形如 http://39.105.196.84 —— 各服务在此基础上拼 /api/...
    public static var origin: String { "\(scheme)://\(host)" }

    /// 形如 http://39.105.196.84/api
    public static var apiBase: String { "\(origin)/api" }
}
