import Testing
import Foundation
@testable import LevelItShared

@Suite("Task Expiry Tests")
struct TaskExpiryTests {

    @Test("创建当天的任务不过期")
    func notExpiredWithinCreationDay() {
        let task = makeTask()
        #expect(!shouldExpire(task))
    }

    @Test("跨日 created 任务应归档过期")
    func createdExpiresOnNextDay() {
        let task = makeTask()
        task.createdAt = dayAgo(1)
        #expect(shouldExpire(task))
    }

    @Test("跨日 synced 任务应归档过期")
    func syncedExpiresOnNextDay() {
        let task = makeTask()
        task.status = .synced
        task.createdAt = dayAgo(1)
        #expect(shouldExpire(task))
    }

    @Test("跨日进行中任务不归档，但不再进入今日待办")
    func previousDayInProgressIsNotPendingToday() {
        let task = makeTask()
        task.status = .inProgress
        task.createdAt = dayAgo(1)
        #expect(!shouldExpire(task))
        #expect(!task.isPendingForDay())
    }

    @Test("跨日暂停任务不归档，但不再进入今日待办")
    func previousDayPausedIsNotPendingToday() {
        let task = makeTask()
        task.status = .paused
        task.createdAt = dayAgo(1)
        #expect(!shouldExpire(task))
        #expect(!task.isPendingForDay())
    }

    @Test("已完成/已结清/已取消/已过期 不再检查")
    func terminalStatesSkipped() {
        for status: TaskStatus in [.completed, .settled, .cancelled, .expired] {
            let task = makeTask()
            task.status = status
            task.createdAt = dayAgo(1)
            #expect(!shouldExpire(task), "Terminal status \(status) should not expire again")
        }
    }

    @Test("当天零点创建仍属于今日待办")
    func atStartOfTodayIsPending() {
        let task = makeTask()
        task.createdAt = Calendar.current.startOfDay(for: Date())
        #expect(!shouldExpire(task))
        #expect(task.isPendingForDay())
    }

    @Test("过期后状态转换成功")
    func expiryTransition() {
        let task = makeTask()
        task.createdAt = dayAgo(1)
        #expect(TaskStateMachine.transition(task, to: .expired))
        #expect(task.status == .expired)
        #expect(task.expiredAt != nil)
    }

    @Test("过期任务不计入欠债")
    func expiredNotCountedAsDebt() {
        let task = makeTask()
        TaskStateMachine.transition(task, to: .expired)
        #expect(!task.status.countsAsDebt)
    }

    // MARK: - Helpers

    /// 模拟过期检查逻辑
    private func shouldExpire(_ task: DebtTask) -> Bool {
        task.shouldExpireForNewDay()
    }

    private func makeTask() -> DebtTask {
        DebtTask(
            foodName: "测试食物",
            foodEmoji: "🍔",
            estimatedCalories: 300,
            taskMode: .mix,
            source: .iPhone
        )
    }

    private func dayAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }
}
