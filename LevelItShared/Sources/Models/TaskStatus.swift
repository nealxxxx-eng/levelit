import Foundation

/// 任务状态 — 8 种状态的完整生命周期
///
/// 状态转换图:
///   created -> synced -> in_progress <-> paused -> completed -> settled
///                                                     |
///   created -> in_progress  (Watch 独立创建, 跳过 synced)
///   created/synced -> expired  (跨日仍未开始)
///   created/synced/in_progress/paused -> cancelled
///
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case created     // 已创建
    case synced      // 已同步到 Watch (iPhone 创建的任务)
    case inProgress  // 运动中
    case paused      // 暂停
    case completed   // 运动完成 (burnedCal >= targetCal)
    case settled     // 已确认结清 (用户看到结果页)
    case cancelled   // 已取消
    case expired     // 未在创建当天开始, 自动归档

    /// 是否为终态 (不可再转换)
    public var isTerminal: Bool {
        switch self {
        case .settled, .cancelled, .expired:
            return true
        default:
            return false
        }
    }

    /// 是否计入"今日欠债"
    public var countsAsDebt: Bool {
        switch self {
        case .created, .synced, .inProgress, .paused:
            return true
        case .completed, .settled, .cancelled, .expired:
            return false
        }
    }

    /// 中文显示名
    public var displayName: String {
        switch self {
        case .created:    return "待开始"
        case .synced:     return "已同步"
        case .inProgress: return "进行中"
        case .paused:     return "已暂停"
        case .completed:  return "已完成"
        case .settled:    return "已结清"
        case .cancelled:  return "已取消"
        case .expired:    return "已过期"
        }
    }
}
