import Foundation
import SwiftData
import LevelItShared

/// 任务过期检查服务 — App 启动时 + 回前台检查
enum TaskExpiryService {

    /// 跨日未开始的任务只保留为历史记录，不带入新一天待磨平队列。
    @MainActor
    @discardableResult
    static func checkAndExpire(in context: ModelContext) -> Int {
        // SwiftData #Predicate 不支持枚举直接比较, 用 fetch all + 内存过滤
        let descriptor = FetchDescriptor<DebtTask>()
        guard let tasks = try? context.fetch(descriptor) else { return 0 }

        var count = 0
        for task in tasks {
            if task.shouldExpireForNewDay() {
                if TaskStateMachine.transition(task, to: .expired) {
                    count += 1
                }
            }
        }

        if count > 0 {
            try? context.save()
        }

        return count
    }
}
