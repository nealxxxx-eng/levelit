import Foundation

/// 热量换算器 — 将食物热量转换为运动时长
///
/// 个性化: 如果用户已填写档案, 按体重修正消耗率
/// 公式: personalizedRate = baseRate × (userWeight / 65.0)
/// 65kg 为基准参考体重 (中国成年人均值附近)
public enum CalorieCalculator {

    private static let referenceWeightKG: Double = 65.0

    /// 计算运动时长 (分钟), 自动读取用户档案做个性化修正
    public static func calculateMinutes(calories: Int, mode: TaskMode) -> Int {
        guard calories > 0 else { return 0 }
        let rate = personalizedRate(for: mode)
        return max(1, Int(ceil(Double(calories) / rate)))
    }

    /// 计算三种模式的运动时长
    public static func calculateAllModes(calories: Int) -> [(mode: TaskMode, minutes: Int)] {
        TaskMode.allCases.map { mode in
            (mode: mode, minutes: calculateMinutes(calories: calories, mode: mode))
        }
    }

    /// 个性化后的每分钟消耗 (kcal/min)
    public static func personalizedRate(for mode: TaskMode) -> Double {
        guard let profile = UserProfileStore.current else {
            return mode.caloriesPerMinute
        }
        let scale = profile.weightKG / referenceWeightKG
        return mode.caloriesPerMinute * scale
    }

    /// 校验热量值是否合理
    public static func validateCalories(_ calories: Int) -> CalorieValidation {
        switch calories {
        case ..<10:
            return .tooLow
        case 10...5000:
            return .valid
        default:
            return .suspicious
        }
    }

    /// Clamp user/AI supplied calories before they enter persisted task state.
    public static func clampedCalories(_ calories: Int) -> Int {
        max(AppConstants.minCalories, min(AppConstants.maxCalories, calories))
    }
}

/// 热量校验结果
public enum CalorieValidation: Equatable, Sendable {
    case valid
    case tooLow
    case suspicious
}
