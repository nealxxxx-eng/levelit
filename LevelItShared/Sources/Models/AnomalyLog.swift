import Foundation
import SwiftData

// MARK: - 异常原因标签

/// 用户标记某天为"异常日"时可勾选的预设原因（多选）
public enum AnomalyReasonTag: String, Codable, CaseIterable, Sendable {
    case businessTrip      // 出差
    case socialDinner      // 聚餐
    case illness           // 生病
    case emotionalEating   // 情绪化进食
    case festival          // 节日/庆祝
    case lateNight         // 熬夜
    case other             // 其他

    public var displayName: String {
        switch self {
        case .businessTrip:    return "出差"
        case .socialDinner:    return "聚餐"
        case .illness:         return "生病"
        case .emotionalEating: return "情绪化进食"
        case .festival:        return "节日庆祝"
        case .lateNight:       return "熬夜"
        case .other:           return "其他"
        }
    }

    public var emoji: String {
        switch self {
        case .businessTrip:    return "✈️"
        case .socialDinner:    return "🍽️"
        case .illness:         return "🤒"
        case .emotionalEating: return "😞"
        case .festival:        return "🎉"
        case .lateNight:       return "🌙"
        case .other:           return "🏷️"
        }
    }
}

// MARK: - 异常日记录

/// 用户在 Stats 页对某一天主观标记"异常"，并写入原因/处置方案；
/// 用于日后趋势分析（先做记录，分析视图后续迭代）。
@Model
public final class AnomalyLog {
    @Attribute(.unique) public var id: String

    /// 异常所属的"日历日"（统一用本地日历的 startOfDay，便于按日聚合）
    public var date: Date

    /// 预设原因标签（JSON-encoded by SwiftData）。多选。
    public var reasonTags: [AnomalyReasonTag]

    /// 自由文本原因（可空；当 tags 已足够表达时用户可不填）
    public var freeReason: String

    /// 处置方案（用户的应对计划，例如"明天加 30 分钟有氧"）
    public var dispositionPlan: String

    /// 创建时间（不等于 date；用于日志/审计用途）
    public var createdAt: Date

    /// 最近一次编辑时间
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        date: Date,
        reasonTags: [AnomalyReasonTag] = [],
        freeReason: String = "",
        dispositionPlan: String = "",
        calendar: Calendar = .current
    ) {
        self.id = id
        self.date = calendar.startOfDay(for: date)
        self.reasonTags = reasonTags
        self.freeReason = freeReason
        self.dispositionPlan = dispositionPlan
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
