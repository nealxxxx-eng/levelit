import Foundation

/// PK 挑战的「运动统计窗口」。
///
/// 进度统计的时间范围是 `[挑战开始, 现在]`：
/// - 下界 = 挑战开始时刻（`acceptedAt ?? createdAt`），挑战开始前的运动不计入；
/// - 上界 = **现在**。只要挑战仍在进行中，从开始到此刻的运动都应计入。
///
/// 历史 bug：旧实现把上界设为 `开始 + durationDays 天`。当挑战已进行超过
/// durationDays 天后，这个上界落在「今天」之前，导致**今天的新运动被错误排除、
/// 而更早的旧运动反而被计入**。`durationDays` 只用于过期判断（见 expiresAt /
/// isNaturallyExpired），不应限制运动统计的上界。
public enum PKProgressWindow {
    /// 返回统计窗口 `[start, max(start, now)]`。
    public static func range(start: Date, now: Date = Date()) -> (start: Date, end: Date) {
        (start, max(start, now))
    }
}
