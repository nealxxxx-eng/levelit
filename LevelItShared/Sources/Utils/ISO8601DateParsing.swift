import Foundation

/// 容错的 ISO8601 解析 / 格式化工具。
///
/// 背景：后端（Node.js）所有时间都用 `new Date().toISOString()` 生成，
/// 输出**带毫秒**，形如 `2026-06-17T10:30:00.000Z`。而 Swift 默认的
/// `ISO8601DateFormatter`（仅 `.withInternetDateTime`）**无法解析带小数秒**
/// 的字符串，会返回 nil —— 这曾导致 PK 挑战的 acceptedAt / expiresAt /
/// completedAt 全部丢失，进而让进度时间窗口、过期倒计时计算错误。
///
/// 这里先按「带毫秒」解析，失败再退回「标准」格式，兼容两种输出；
/// 输出统一带毫秒，保证与后端格式一致、往返无损。
public enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain = ISO8601DateFormatter()

    /// 解析后端时间串，自动兼容带 / 不带毫秒；非法串返回 nil。
    public static func date(from string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }

    /// 统一输出带毫秒的 ISO8601 串（与后端 `toISOString()` 一致）。
    public static func string(from date: Date) -> String {
        fractional.string(from: date)
    }
}
