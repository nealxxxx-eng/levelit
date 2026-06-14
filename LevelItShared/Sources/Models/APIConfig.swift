import Foundation

/// 后端地址统一配置。
///
/// 切换到 HTTPS 时只需把 `scheme` 改为 "https"、`host` 改为你的域名，
/// 全 App 的网络层（认证 / PK / 社交 / AI 分析）一处生效；
/// 同时记得移除 Info.plist 里的 ATS 明文例外。
public enum APIConfig {
    // 切 HTTPS 时改这三行即可（并移除 Info.plist 的 ATS 例外）：
    //   scheme = "https"; host = "levelit.duckdns.org"; port = 8443
    public static let scheme = "http"
    public static let host = "39.105.196.84"
    public static let port: Int? = nil   // 非默认端口时填（如 HTTPS 8443）

    /// 形如 http://39.105.196.84 或 https://levelit.duckdns.org:8443
    public static var origin: String {
        if let port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    /// 形如 <origin>/api
    public static var apiBase: String { "\(origin)/api" }
}
