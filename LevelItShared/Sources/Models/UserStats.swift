import Foundation
import SwiftData

/// 用户统计 — 单例模型, id 固定为 "current"
@Model
public final class UserStats {
    @Attribute(.unique) public var id: String
    public var currentStreakDays: Int
    public var longestStreakDays: Int
    public var totalTasksCreated: Int
    public var totalTasksCompleted: Int
    public var totalCaloriesBurned: Int
    public var lastCompletionDate: Date?

    public init() {
        self.id = "current"
        self.currentStreakDays = 0
        self.longestStreakDays = 0
        self.totalTasksCreated = 0
        self.totalTasksCompleted = 0
        self.totalCaloriesBurned = 0
        self.lastCompletionDate = nil
    }

    /// 记录一次任务完成, 更新 Streak
    public func recordCompletion(burnedCalories: Int, on date: Date = Date()) {
        totalTasksCompleted += 1
        totalCaloriesBurned += burnedCalories

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        if let lastDate = lastCompletionDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

            switch daysBetween {
            case 0:
                // 同一天再次完成, streak 不变
                break
            case 1:
                // 连续天, streak +1
                currentStreakDays += 1
            default:
                // 断了, 重新开始
                currentStreakDays = 1
            }
        } else {
            // 第一次完成
            currentStreakDays = 1
        }

        longestStreakDays = max(longestStreakDays, currentStreakDays)
        lastCompletionDate = date
    }

    /// 计算当前实际 streak (考虑今天是否已完成)
    public func currentStreak(asOf date: Date = Date()) -> Int {
        guard let lastDate = lastCompletionDate else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let lastDay = calendar.startOfDay(for: lastDate)
        let daysSinceLast = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

        switch daysSinceLast {
        case 0:
            return currentStreakDays  // 今天已完成
        case 1:
            return currentStreakDays  // 昨天完成, 今天还有机会
        default:
            return 0                  // 断了
        }
    }
}
