import Foundation
import SwiftData

// MARK: - 判定分类（持久化用）

/// MealClassifier 输出的简化标签，存到 MealIntake 用于历史浏览。
/// 不直接存 MealVerdict 是因为枚举关联值不便 SwiftData 序列化。
public enum MealVerdictKind: String, Codable, CaseIterable, Sendable {
    case normal     // 正餐达标（±容差内）
    case over       // 正餐超标
    case under      // 正餐欠摄
    case snack      // 加餐
    case snackBuffered
    case snackOver

    public var displayName: String {
        switch self {
        case .normal:        return "达标"
        case .over:          return "超标"
        case .under:         return "偏少"
        case .snack:         return "加餐"
        case .snackBuffered: return "缓冲内"
        case .snackOver:     return "加餐超额"
        }
    }
}

public extension MealVerdict {
    /// 转成持久化用的简化标签
    var kind: MealVerdictKind {
        switch self {
        case .snack:         return .snack
        case .bufferedSnack: return .snackBuffered
        case .overSnack:     return .snackOver
        case .normalMeal:    return .normal
        case .overMeal:      return .over
        case .underMeal:     return .under
        }
    }
}

// MARK: - 摄入记录

/// 每次拍照都会记录一条；与 DebtTask 解耦。
/// 用途：今日摄入统计、同餐累加判定、历史浏览。
@Model
public final class MealIntake {
    @Attribute(.unique) public var id: String

    public var foodName: String
    public var foodEmoji: String

    /// 用户实际份额对应的卡路里（已扣除分餐）
    public var estimatedCalories: Int
    /// AI 原始识别热量（分餐前）
    public var originalCalories: Int
    /// 分餐人数（1 = 独享）
    public var diners: Int

    public var foodImageFileName: String?

    /// 拍照实际时间（用作判定餐次窗口和按日聚合）
    public var takenAt: Date

    /// 落入哪个餐次（拍照当时由 MealQuotaConfig 判定，不随后续配置漂移）
    public var mealKind: MealKind

    /// 判定结果标签
    public var verdictKind: MealVerdictKind

    /// 关联的磨平任务 id（仅当 verdictKind 为 over/snack 时可能非空）
    public var debtTaskId: String?

    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        foodName: String,
        foodEmoji: String,
        estimatedCalories: Int,
        originalCalories: Int,
        diners: Int = 1,
        foodImageFileName: String? = nil,
        takenAt: Date = Date(),
        mealKind: MealKind,
        verdictKind: MealVerdictKind,
        debtTaskId: String? = nil
    ) {
        self.id = id
        self.foodName = foodName
        self.foodEmoji = foodEmoji
        self.estimatedCalories = estimatedCalories
        self.originalCalories = originalCalories
        self.diners = diners
        self.foodImageFileName = foodImageFileName
        self.takenAt = takenAt
        self.mealKind = mealKind
        self.verdictKind = verdictKind
        self.debtTaskId = debtTaskId
        self.createdAt = Date()
    }
}
