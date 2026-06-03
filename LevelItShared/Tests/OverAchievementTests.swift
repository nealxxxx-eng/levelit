import Testing
import Foundation
@testable import LevelItShared

@Suite("Over-Achievement Tests")
struct OverAchievementTests {

    @Test("正好完成 100%: 不算超额")
    func exactCompletion() {
        let task = makeTask(target: 300)
        task.updateProgress(burnedCalories: 300, durationSeconds: 600)
        #expect(task.progressPercent == 100)
        #expect(!task.isOverAchieved)
    }

    @Test("完成 119%: 不算超额 (阈值 120%)")
    func justUnderThreshold() {
        let task = makeTask(target: 300)
        task.updateProgress(burnedCalories: 357, durationSeconds: 700)
        #expect(task.progressPercent == 119)
        #expect(!task.isOverAchieved)
    }

    @Test("完成 120%: 算超额")
    func exactThreshold() {
        let task = makeTask(target: 300)
        task.updateProgress(burnedCalories: 360, durationSeconds: 720)
        #expect(task.progressPercent == 120)
        #expect(task.isOverAchieved)
    }

    @Test("完成 150%: 算超额")
    func wellOverThreshold() {
        let task = makeTask(target: 200)
        task.updateProgress(burnedCalories: 300, durationSeconds: 900)
        #expect(task.progressPercent == 150)
        #expect(task.isOverAchieved)
    }

    @Test("部分完成 50%: 不算超额")
    func partialCompletion() {
        let task = makeTask(target: 400)
        task.updateProgress(burnedCalories: 200, durationSeconds: 300)
        #expect(task.progressPercent == 50)
        #expect(!task.isOverAchieved)
    }

    @Test("进度百分比上限 999%")
    func progressCap() {
        let task = makeTask(target: 100)
        task.updateProgress(burnedCalories: 10000, durationSeconds: 3600)
        #expect(task.progressPercent == 999)
    }

    @Test("target 为 0 时不崩溃")
    func zeroTargetSafe() {
        let task = makeTask(target: 0)
        task.updateProgress(burnedCalories: 100, durationSeconds: 60)
        // 不应崩溃, progressPercent 保持 0
        #expect(task.burnedCalories == 100)
    }

    // MARK: - Helper

    private func makeTask(target: Int) -> DebtTask {
        let task = DebtTask(
            foodName: "测试食物",
            foodEmoji: "🍔",
            estimatedCalories: target,
            taskMode: .mix,
            source: .watch
        )
        task.targetBurnCalories = target
        return task
    }
}
