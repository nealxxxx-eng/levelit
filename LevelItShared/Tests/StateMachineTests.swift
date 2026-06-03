import Testing
import Foundation
@testable import LevelItShared

@Suite("TaskStateMachine Tests")
struct StateMachineTests {

    // MARK: - 合法转换

    @Test("created -> synced (iPhone 创建同步到 Watch)")
    func createdToSynced() {
        let task = makeTask()
        #expect(TaskStateMachine.transition(task, to: .synced))
        #expect(task.status == .synced)
    }

    @Test("created -> inProgress (Watch 独立创建直接开始)")
    func createdToInProgress() {
        let task = makeTask(source: .watch)
        #expect(TaskStateMachine.transition(task, to: .inProgress))
        #expect(task.status == .inProgress)
    }

    @Test("synced -> inProgress (Watch 开始运动)")
    func syncedToInProgress() {
        let task = makeTask()
        TaskStateMachine.transition(task, to: .synced)
        #expect(TaskStateMachine.transition(task, to: .inProgress))
        #expect(task.status == .inProgress)
    }

    @Test("inProgress -> paused -> inProgress (暂停恢复)")
    func pauseAndResume() {
        let task = makeTask(source: .watch)
        TaskStateMachine.transition(task, to: .inProgress)

        #expect(TaskStateMachine.transition(task, to: .paused))
        #expect(task.status == .paused)

        #expect(TaskStateMachine.transition(task, to: .inProgress))
        #expect(task.status == .inProgress)
    }

    @Test("inProgress -> completed -> settled (完整结清流程)")
    func completeAndSettle() {
        let task = makeTask(source: .watch)
        TaskStateMachine.transition(task, to: .inProgress)

        #expect(TaskStateMachine.transition(task, to: .completed))
        #expect(task.status == .completed)
        #expect(task.completedAt != nil)

        #expect(TaskStateMachine.transition(task, to: .settled))
        #expect(task.status == .settled)
    }

    @Test("created -> expired (跨日未开始)")
    func createdToExpired() {
        let task = makeTask()
        #expect(TaskStateMachine.transition(task, to: .expired))
        #expect(task.status == .expired)
        #expect(task.expiredAt != nil)
    }

    @Test("synced -> expired (跨日未开始)")
    func syncedToExpired() {
        let task = makeTask()
        TaskStateMachine.transition(task, to: .synced)
        #expect(TaskStateMachine.transition(task, to: .expired))
        #expect(task.status == .expired)
    }

    // MARK: - 取消

    @Test("各状态 -> cancelled")
    func cancelFromVariousStates() {
        let states: [TaskStatus] = [.created, .synced, .inProgress, .paused]
        for startStatus in states {
            let task = makeTask(source: .watch)
            task.status = startStatus
            #expect(TaskStateMachine.canTransition(from: startStatus, to: .cancelled),
                    "Should be able to cancel from \(startStatus)")
        }
    }

    // MARK: - 非法转换

    @Test("settled 是终态, 不可转换")
    func settledIsTerminal() {
        #expect(!TaskStateMachine.canTransition(from: .settled, to: .created))
        #expect(!TaskStateMachine.canTransition(from: .settled, to: .inProgress))
        #expect(!TaskStateMachine.canTransition(from: .settled, to: .cancelled))
    }

    @Test("expired 是终态, 不可转换")
    func expiredIsTerminal() {
        #expect(!TaskStateMachine.canTransition(from: .expired, to: .created))
        #expect(!TaskStateMachine.canTransition(from: .expired, to: .inProgress))
    }

    @Test("cancelled 是终态, 不可转换")
    func cancelledIsTerminal() {
        #expect(!TaskStateMachine.canTransition(from: .cancelled, to: .created))
        #expect(!TaskStateMachine.canTransition(from: .cancelled, to: .inProgress))
    }

    @Test("不能从 created 直接跳到 completed")
    func cannotSkipToCompleted() {
        #expect(!TaskStateMachine.canTransition(from: .created, to: .completed))
    }

    @Test("不能从 completed 回退到 inProgress")
    func cannotRevertFromCompleted() {
        #expect(!TaskStateMachine.canTransition(from: .completed, to: .inProgress))
    }

    @Test("不能从 paused 直接到 completed")
    func cannotCompleteFromPaused() {
        #expect(!TaskStateMachine.canTransition(from: .paused, to: .completed))
    }

    @Test("transition 返回 false 时状态不变")
    func failedTransitionPreservesState() {
        let task = makeTask()
        let result = TaskStateMachine.transition(task, to: .completed)
        #expect(!result)
        #expect(task.status == .created)
    }

    // MARK: - Helper

    private func makeTask(source: TaskSource = .iPhone) -> DebtTask {
        DebtTask(
            foodName: "测试食物",
            foodEmoji: "🍔",
            estimatedCalories: 300,
            taskMode: .mix,
            source: source
        )
    }
}
