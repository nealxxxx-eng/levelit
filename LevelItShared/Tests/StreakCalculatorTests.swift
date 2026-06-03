import Testing
import Foundation
@testable import LevelItShared

@Suite("Streak & Achievement Tests")
struct StreakCalculatorTests {

    // MARK: - Streak 计算

    @Test("首次完成: streak = 1")
    func firstCompletion() {
        let stats = UserStats()
        stats.recordCompletion(burnedCalories: 300)
        #expect(stats.currentStreakDays == 1)
        #expect(stats.longestStreakDays == 1)
    }

    @Test("同一天多次完成: streak 不增加")
    func sameDayMultiple() {
        let stats = UserStats()
        let today = Date()
        stats.recordCompletion(burnedCalories: 200, on: today)
        stats.recordCompletion(burnedCalories: 300, on: today)
        #expect(stats.currentStreakDays == 1)
        #expect(stats.totalTasksCompleted == 2)
        #expect(stats.totalCaloriesBurned == 500)
    }

    @Test("连续两天: streak = 2")
    func consecutiveDays() {
        let stats = UserStats()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        stats.recordCompletion(burnedCalories: 200, on: yesterday)
        stats.recordCompletion(burnedCalories: 300, on: Date())
        #expect(stats.currentStreakDays == 2)
    }

    @Test("断了一天: streak 重置为 1")
    func brokenStreak() {
        let stats = UserStats()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        stats.recordCompletion(burnedCalories: 200, on: twoDaysAgo)
        #expect(stats.currentStreakDays == 1)

        // 跳过昨天, 今天完成
        stats.recordCompletion(burnedCalories: 300, on: Date())
        #expect(stats.currentStreakDays == 1)  // 重置
    }

    @Test("longestStreak 保留历史最高")
    func longestStreakPreserved() {
        let stats = UserStats()
        let cal = Calendar.current

        // 连续 3 天
        for i in (0...2).reversed() {
            let date = cal.date(byAdding: .day, value: -i, to: Date())!
            stats.recordCompletion(burnedCalories: 100, on: date)
        }
        #expect(stats.currentStreakDays == 3)
        #expect(stats.longestStreakDays == 3)

        // 断了两天后重新开始
        let futureDate = cal.date(byAdding: .day, value: 3, to: Date())!
        stats.recordCompletion(burnedCalories: 100, on: futureDate)
        #expect(stats.currentStreakDays == 1)
        #expect(stats.longestStreakDays == 3)  // 保留历史
    }

    // MARK: - currentStreak(asOf:)

    @Test("今天已完成: 返回当前 streak")
    func currentStreakToday() {
        let stats = UserStats()
        let today = Date()
        stats.recordCompletion(burnedCalories: 200, on: today)
        #expect(stats.currentStreak(asOf: today) == 1)
    }

    @Test("昨天完成, 今天未完成: 仍返回当前 streak (还有机会)")
    func currentStreakYesterday() {
        let stats = UserStats()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        stats.recordCompletion(burnedCalories: 200, on: yesterday)
        #expect(stats.currentStreak(asOf: Date()) == 1)
    }

    @Test("前天完成, streak 断了: 返回 0")
    func currentStreakBroken() {
        let stats = UserStats()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        stats.recordCompletion(burnedCalories: 200, on: twoDaysAgo)
        #expect(stats.currentStreak(asOf: Date()) == 0)
    }

    @Test("从未完成: 返回 0")
    func currentStreakNever() {
        let stats = UserStats()
        #expect(stats.currentStreak() == 0)
    }

    // MARK: - 徽章解锁

    @Test("3 天解锁三天新手")
    func streak3Achievement() {
        #expect(AchievementType.highestAchievable(forStreak: 3) == .streak3)
    }

    @Test("7 天解锁七天战士")
    func streak7Achievement() {
        #expect(AchievementType.highestAchievable(forStreak: 7) == .streak7)
    }

    @Test("14 天解锁半月达人")
    func streak14Achievement() {
        #expect(AchievementType.highestAchievable(forStreak: 14) == .streak14)
    }

    @Test("30 天解锁月度传奇")
    func streak30Achievement() {
        #expect(AchievementType.highestAchievable(forStreak: 30) == .streak30)
    }

    @Test("2 天不解锁任何徽章")
    func noAchievement() {
        #expect(AchievementType.highestAchievable(forStreak: 2) == nil)
    }

    @Test("10 天返回七天战士 (最高可解锁)")
    func highestAchievable() {
        #expect(AchievementType.highestAchievable(forStreak: 10) == .streak7)
    }
}
