import Testing
import Foundation
@testable import LevelItShared

@Suite("WC Sync & Serialization Tests")
struct WCSyncTests {

    // MARK: - DebtTask 序列化/反序列化

    @Test("DebtTask toDict/fromDict 往返不丢数据")
    func roundTrip() {
        let original = DebtTask(
            id: "test-123",
            foodName: "黑糖珍珠奶茶",
            foodEmoji: "🧋",
            foodImageFileName: "test-123.heic",
            estimatedCalories: 340,
            taskMode: .mix,
            source: .iPhone
        )
        original.status = .inProgress
        original.progressPercent = 45
        original.burnedCalories = 153
        original.durationSeconds = 420
        original.lastSyncAt = Date()
        original.isOverAchieved = false

        let dict = original.toDict()
        let restored = DebtTask.fromDict(dict)

        #expect(restored != nil)
        guard let restored else { return }

        #expect(restored.id == original.id)
        #expect(restored.foodName == original.foodName)
        #expect(restored.foodEmoji == original.foodEmoji)
        #expect(restored.foodImageFileName == original.foodImageFileName)
        #expect(restored.estimatedCalories == original.estimatedCalories)
        #expect(restored.taskLevel == original.taskLevel)
        #expect(restored.taskMode == original.taskMode)
        #expect(restored.targetBurnCalories == original.targetBurnCalories)
        #expect(restored.status == original.status)
        #expect(restored.progressPercent == original.progressPercent)
        #expect(restored.burnedCalories == original.burnedCalories)
        #expect(restored.durationSeconds == original.durationSeconds)
        #expect(restored.source == original.source)
        #expect(restored.isOverAchieved == original.isOverAchieved)
    }

    @Test("fromDict 缺少必填字段返回 nil")
    func missingRequiredFields() {
        let incomplete: [String: Any] = [
            "id": "test-123",
            "foodName": "奶茶",
            // 缺少 estimatedCalories, taskMode, source
        ]
        #expect(DebtTask.fromDict(incomplete) == nil)
    }

    @Test("fromDict 错误类型返回 nil")
    func wrongTypes() {
        let wrong: [String: Any] = [
            "id": "test",
            "foodName": "奶茶",
            "estimatedCalories": "not a number",  // 应为 Int
            "taskMode": "walk",
            "source": "iPhone",
        ]
        #expect(DebtTask.fromDict(wrong) == nil)
    }

    @Test("fromDict 无效 taskMode 返回 nil")
    func invalidTaskMode() {
        let invalid: [String: Any] = [
            "id": "test",
            "foodName": "奶茶",
            "estimatedCalories": 300,
            "taskMode": "fly",  // 不存在的模式
            "source": "iPhone",
        ]
        #expect(DebtTask.fromDict(invalid) == nil)
    }

    // MARK: - 时间戳去重

    @Test("新消息时间戳大于已处理时间戳: 应处理")
    func newerMessageAccepted() {
        var lastProcessed: [String: TimeInterval] = [:]
        let taskId = "task-1"
        let msgTimestamp = Date().timeIntervalSince1970

        let shouldProcess = shouldProcessMessage(
            taskId: taskId,
            timestamp: msgTimestamp,
            lastProcessed: &lastProcessed
        )

        #expect(shouldProcess)
        #expect(lastProcessed[taskId] == msgTimestamp)
    }

    @Test("旧消息时间戳小于已处理时间戳: 应忽略")
    func olderMessageRejected() {
        var lastProcessed: [String: TimeInterval] = ["task-1": 1000.0]

        let shouldProcess = shouldProcessMessage(
            taskId: "task-1",
            timestamp: 999.0,
            lastProcessed: &lastProcessed
        )

        #expect(!shouldProcess)
        #expect(lastProcessed["task-1"] == 1000.0)  // 不被覆盖
    }

    @Test("相同时间戳: 应忽略 (防重复)")
    func sameTimestampRejected() {
        var lastProcessed: [String: TimeInterval] = ["task-1": 1000.0]

        let shouldProcess = shouldProcessMessage(
            taskId: "task-1",
            timestamp: 1000.0,
            lastProcessed: &lastProcessed
        )

        #expect(!shouldProcess)
    }

    @Test("不同 taskId 互不影响")
    func independentTaskIds() {
        var lastProcessed: [String: TimeInterval] = ["task-1": 1000.0]

        let shouldProcess = shouldProcessMessage(
            taskId: "task-2",
            timestamp: 500.0,
            lastProcessed: &lastProcessed
        )

        #expect(shouldProcess)  // task-2 没有记录, 任何时间戳都接受
    }

    // MARK: - Helpers

    /// 模拟时间戳去重逻辑 (与 WatchSyncReceiver/WorkoutSyncService 保持一致)
    private func shouldProcessMessage(
        taskId: String,
        timestamp: TimeInterval,
        lastProcessed: inout [String: TimeInterval]
    ) -> Bool {
        if let last = lastProcessed[taskId], timestamp <= last {
            return false
        }
        lastProcessed[taskId] = timestamp
        return true
    }
}
