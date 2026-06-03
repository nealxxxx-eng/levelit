import Foundation
import SwiftData

/// 成就徽章类型
public enum AchievementType: String, Codable, CaseIterable, Sendable {
    case streak3  = "三天新手"
    case streak7  = "七天战士"
    case streak14 = "半月达人"
    case streak30 = "月度传奇"

    /// 需要的连续天数
    public var requiredDays: Int {
        switch self {
        case .streak3:  return 3
        case .streak7:  return 7
        case .streak14: return 14
        case .streak30: return 30
        }
    }

    /// 图标名 (SF Symbol)
    public var iconName: String {
        switch self {
        case .streak3:  return "star.fill"
        case .streak7:  return "star.circle.fill"
        case .streak14: return "medal.fill"
        case .streak30: return "crown.fill"
        }
    }

    /// 按天数从低到高排序, 返回应解锁的最高徽章
    public static func highestAchievable(forStreak days: Int) -> AchievementType? {
        // 从高到低检查
        for type in [streak30, streak14, streak7, streak3] {
            if days >= type.requiredDays {
                return type
            }
        }
        return nil
    }
}

/// 成就徽章记录
@Model
public final class Achievement {
    @Attribute(.unique) public var id: String
    public var type: AchievementType
    public var unlockedAt: Date
    public var streakDays: Int

    public init(
        id: String = UUID().uuidString,
        type: AchievementType,
        streakDays: Int
    ) {
        self.id = id
        self.type = type
        self.unlockedAt = Date()
        self.streakDays = streakDays
    }
}
