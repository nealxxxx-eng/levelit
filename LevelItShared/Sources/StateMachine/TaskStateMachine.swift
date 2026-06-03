import Foundation

/// 任务状态机 — 管理 DebtTask 的合法状态转换
///
/// 状态转换图:
///
///   created -----> synced -----> in_progress <----> paused
///     |              |               |                |
///     |              |               v                |
///     |              |           completed            |
///     |              |               |                |
///     |              |               v                |
///     |              |            settled             |
///     |              |                                |
///     +---> expired  +---> expired                    |
///     +---> cancelled+---> cancelled <--- cancelled <-+
///
///   Watch 独立: created -> in_progress (跳过 synced)
///
public enum TaskStateMachine {

    /// 检查状态转换是否合法
    public static func canTransition(from: TaskStatus, to: TaskStatus) -> Bool {
        let allowed = allowedTransitions[from] ?? []
        return allowed.contains(to)
    }

    /// 执行状态转换, 成功返回 true
    @discardableResult
    public static func transition(_ task: DebtTask, to newStatus: TaskStatus) -> Bool {
        guard canTransition(from: task.status, to: newStatus) else {
            return false
        }

        task.status = newStatus

        switch newStatus {
        case .completed:
            task.completedAt = Date()
        case .expired:
            task.expiredAt = Date()
        default:
            break
        }

        return true
    }

    /// 所有合法的状态转换表
    public static let allowedTransitions: [TaskStatus: Set<TaskStatus>] = [
        .created: [
            .synced,       // iPhone 创建 -> 同步到 Watch
            .inProgress,   // Watch 独立创建 -> 直接开始
            .cancelled,
            .expired,      // 跨日仍未开始
        ],
        .synced: [
            .inProgress,   // Watch 开始运动
            .cancelled,
            .expired,      // 跨日仍未开始
        ],
        .inProgress: [
            .paused,       // 暂停
            .completed,    // 达到目标
            .cancelled,
        ],
        .paused: [
            .inProgress,   // 恢复运动
            .cancelled,
        ],
        .completed: [
            .settled,      // 用户确认结清
        ],
        // settled, cancelled, expired 是终态
        .settled: [],
        .cancelled: [],
        .expired: [],
    ]
}
