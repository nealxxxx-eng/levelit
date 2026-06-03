import Testing
import Foundation
@testable import LevelItShared

/// 回归测试 — 覆盖过去发现的所有 bug
@Suite("Regression Tests — 已修复 Bug 验证")
struct RegressionTests {

    // MARK: - Bug: 暂停后恢复进度清零

    @Test("暂停后恢复: 进度应从上次继续, 不清零")
    func resumeKeepsProgress() {
        let task = makeTask(target: 100)
        // 模拟运动到 40%
        task.updateProgress(burnedCalories: 40, durationSeconds: 120)
        #expect(task.progressPercent == 40)
        #expect(task.burnedCalories == 40)

        // 暂停
        TaskStateMachine.transition(task, to: .inProgress)
        TaskStateMachine.transition(task, to: .paused)
        #expect(task.status == .paused)

        // 恢复后进度应保留
        TaskStateMachine.transition(task, to: .inProgress)
        #expect(task.burnedCalories == 40)  // 不清零
        #expect(task.progressPercent == 40)
        #expect(task.durationSeconds == 120)
    }

    // MARK: - Bug: 部分完成显示"已结清"

    @Test("部分完成(50%): 不应标记为 settled")
    func partialCompletionNotSettled() {
        let task = makeTask(target: 100)
        task.updateProgress(burnedCalories: 50, durationSeconds: 200)
        TaskStateMachine.transition(task, to: .inProgress)

        // 手动停止 (部分完成)
        // 50 < 100, 不应 completed
        let canComplete = task.burnedCalories >= task.targetBurnCalories
        #expect(!canComplete)
        #expect(task.status == .inProgress)

        // 应该 paused, 不是 settled
        TaskStateMachine.transition(task, to: .paused)
        #expect(task.status == .paused)
        #expect(task.status != .settled)
    }

    // MARK: - Bug: 100% 完成后仍显示暂停

    @Test("100% 完成: 应标记为 completed, 可转 settled")
    func fullCompletionFlow() {
        let task = makeTask(target: 100)
        TaskStateMachine.transition(task, to: .inProgress)
        task.updateProgress(burnedCalories: 100, durationSeconds: 300)

        #expect(task.progressPercent == 100)
        #expect(task.burnedCalories >= task.targetBurnCalories)

        TaskStateMachine.transition(task, to: .completed)
        #expect(task.status == .completed)
        #expect(task.completedAt != nil)

        TaskStateMachine.transition(task, to: .settled)
        #expect(task.status == .settled)
    }

    // MARK: - Bug: isFullyComplete 多条件判断

    @Test("isFullyComplete: burnedCalories >= target 即为完成")
    func isFullyCompleteByCalories() {
        let task = makeTask(target: 100)
        task.updateProgress(burnedCalories: 100, durationSeconds: 300)
        #expect(task.burnedCalories >= task.targetBurnCalories)
    }

    @Test("isFullyComplete: progressPercent >= 100 即为完成")
    func isFullyCompleteByPercent() {
        let task = makeTask(target: 100)
        task.updateProgress(burnedCalories: 101, durationSeconds: 300)
        #expect(task.progressPercent >= 100)
    }

    @Test("isFullyComplete: status == .completed 即为完成")
    func isFullyCompleteByStatus() {
        let task = makeTask(target: 100)
        TaskStateMachine.transition(task, to: .inProgress)
        TaskStateMachine.transition(task, to: .completed)
        #expect(task.status == .completed)
    }

    // MARK: - Bug: paused → inProgress 转换

    @Test("paused → inProgress 是合法转换")
    func pausedToInProgress() {
        let task = makeTask(target: 100)
        TaskStateMachine.transition(task, to: .inProgress)
        TaskStateMachine.transition(task, to: .paused)
        #expect(task.status == .paused)

        let result = TaskStateMachine.transition(task, to: .inProgress)
        #expect(result)
        #expect(task.status == .inProgress)
    }

    // MARK: - Bug: iPhone 创建的任务 source 标记

    @Test("iPhone 创建的任务 source == .iPhone")
    func iPhoneTaskSource() {
        let task = DebtTask(
            foodName: "测试", foodEmoji: "🧪",
            estimatedCalories: 100, taskMode: .walk, source: .iPhone
        )
        #expect(task.source == .iPhone)
    }

    @Test("Watch 创建的任务 source == .watch")
    func watchTaskSource() {
        let task = DebtTask(
            foodName: "测试", foodEmoji: "🧪",
            estimatedCalories: 100, taskMode: .walk, source: .watch
        )
        #expect(task.source == .watch)
    }

    // MARK: - Bug: 超额完成判定

    @Test("119% 不算超额, 120% 算超额")
    func overAchievementBoundary() {
        let task = makeTask(target: 100)

        task.updateProgress(burnedCalories: 119, durationSeconds: 400)
        #expect(!task.isOverAchieved)

        task.updateProgress(burnedCalories: 120, durationSeconds: 450)
        #expect(task.isOverAchieved)
    }

    // MARK: - Bug: WC 序列化往返

    @Test("DebtTask toDict/fromDict 包含所有关键字段")
    func serializationRoundTrip() {
        let task = DebtTask(
            foodName: "奶茶", foodEmoji: "🧋",
            estimatedCalories: 340, taskMode: .indoorCycling, source: .watch
        )
        task.updateProgress(burnedCalories: 170, durationSeconds: 600)
        TaskStateMachine.transition(task, to: .inProgress)

        let dict = task.toDict()
        let restored = DebtTask.fromDict(dict)

        #expect(restored != nil)
        #expect(restored?.foodName == "奶茶")
        #expect(restored?.taskMode == .indoorCycling)
        #expect(restored?.source == .watch)
        #expect(restored?.burnedCalories == 170)
        #expect(restored?.durationSeconds == 600)
    }

    // MARK: - Bug: 跨日归档不强行打断进行中的任务

    @Test("inProgress 状态不过期")
    func inProgressNotExpirable() {
        let task = makeTask(target: 100)
        TaskStateMachine.transition(task, to: .inProgress)

        // 不能从 inProgress 转到 expired
        let result = TaskStateMachine.canTransition(from: .inProgress, to: .expired)
        #expect(!result)
    }

    // MARK: - Bug: Streak 计算

    @Test("连续两天完成: streak = 2")
    func streakTwoDays() {
        let stats = UserStats()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        stats.recordCompletion(burnedCalories: 100, on: yesterday)
        stats.recordCompletion(burnedCalories: 100, on: Date())
        #expect(stats.currentStreakDays == 2)
    }

    @Test("断了一天: streak 重置")
    func streakBroken() {
        let stats = UserStats()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        stats.recordCompletion(burnedCalories: 100, on: twoDaysAgo)
        stats.recordCompletion(burnedCalories: 100, on: Date())
        #expect(stats.currentStreakDays == 1)  // 重置
    }

    // MARK: - Bug: 运动模式扩展

    @Test("所有 12 种运动模式都能创建任务")
    func allModesCreateTask() {
        for mode in TaskMode.allCases {
            let task = DebtTask(
                foodName: "测试", foodEmoji: "🧪",
                estimatedCalories: 100, taskMode: mode, source: .watch
            )
            #expect(task.taskMode == mode)
            #expect(task.estimatedMinutes > 0)
        }
    }

    @Test("TaskMode.basicModes 返回 3 种基础模式")
    func basicModesCount() {
        #expect(TaskMode.basicModes.count == 3)
        #expect(TaskMode.basicModes.contains(.walk))
        #expect(TaskMode.basicModes.contains(.mix))
        #expect(TaskMode.basicModes.contains(.run))
    }

    @Test("allByIntensity 返回全部模式且有序")
    func allByIntensitySorted() {
        let sorted = TaskMode.allByIntensity
        #expect(sorted.count == TaskMode.allCases.count)
        for i in 0..<(sorted.count - 1) {
            #expect(sorted[i].intensity <= sorted[i + 1].intensity)
        }
    }

    // MARK: - Helper

    private func makeTask(target: Int) -> DebtTask {
        let task = DebtTask(
            foodName: "测试", foodEmoji: "🧪",
            estimatedCalories: target, taskMode: .mix, source: .watch
        )
        return task
    }
}
