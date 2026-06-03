import Foundation

// MARK: - 判定结果

/// 餐次分类 + 配额校验的判定结果
public enum MealVerdict: Equatable, Sendable {

    /// 加餐：直接进磨平任务流，按整张照片热量计入。
    case snack(kcal: Int)

    /// 加餐在每日缓冲内：记录摄入事实，但不生成磨平任务。
    case bufferedSnack(actualCalories: Int, bufferCalories: Int)

    /// 加餐超过每日缓冲：只对新增超额部分生成磨平任务。
    case overSnack(actualCalories: Int, bufferCalories: Int, gap: Int)

    /// 正餐达标：在 ±tolerance 范围内，提示"达标，不计入磨平"。
    /// quotaCalories 为该餐配额上限，actualCalories 为本餐识别热量。
    case normalMeal(kind: MealKind, actualCalories: Int, quotaCalories: Int)

    /// 正餐超标：actual − quotaUpperBound > 0，gap 即建议进入磨平的"热量缺口"。
    /// 用户可在确认页调整 gap。
    case overMeal(kind: MealKind, actualCalories: Int, quotaCalories: Int, gap: Int)

    /// 正餐欠摄：actual 远低于配额下限。当前不阻断磨平流程，由调用方决定 UI 提示策略。
    /// 不强制进任务（吃得少不需要"还债"）。
    case underMeal(kind: MealKind, actualCalories: Int, quotaCalories: Int, deficit: Int)

    /// 是否需要进入磨平任务流
    public var shouldCreateTask: Bool {
        switch self {
        case .snack, .overSnack:    return true
        case .overMeal:             return true
        case .bufferedSnack:        return false
        case .normalMeal, .underMeal: return false
        }
    }

    /// 进入磨平任务时使用的卡路里（snack=整张；overMeal=gap）
    public var taskCalories: Int {
        switch self {
        case .snack(let k):                       return k
        case .overSnack(_, _, let gap):           return gap
        case .bufferedSnack:                      return 0
        case .overMeal(_, _, _, let gap):         return gap
        case .normalMeal, .underMeal:             return 0
        }
    }
}

// MARK: - 分类器（纯函数）

/// 拍照后的餐次分类 + 偏差判断。
///
/// 调用前提：caller 已拿到 AI 识别的本餐热量；MealClassifier 不发起任何 IO。
public enum MealClassifier {

    /// 单张照片版本：按整张照片的卡路里判定。
    /// - Parameters:
    ///   - kcal: 本张照片的预估卡路里（已扣除分餐份额）。必须 ≥ 0。
    ///   - date: 拍照时间（用于落入哪个餐次窗口）。
    ///   - profile: 用户档案。若为 nil（新用户未完成 onboarding），全部按加餐处理。
    ///   - config: 餐次配额配置；默认 `.default`。
    ///   - calendar: 日历，便于测试注入。
    public static func classify(
        kcal: Int,
        at date: Date,
        profile: UserProfile?,
        config: MealQuotaConfig = .default,
        calendar: Calendar = .current
    ) -> MealVerdict {
        return classify(
            cumulativeKcal: max(0, kcal),
            previousCumulativeKcal: 0,
            at: date,
            profile: profile,
            config: config,
            calendar: calendar
        )
    }

    /// 累加版本：当同一餐次内已识别若干张照片时，由调用方累加后传入，避免重复触发"达标"。
    /// - Parameter cumulativeKcal: 该时间窗口内（含本张）的累计卡路里。
    public static func classify(
        cumulativeKcal: Int,
        previousCumulativeKcal: Int = 0,
        at date: Date,
        profile: UserProfile?,
        config: MealQuotaConfig = .default,
        calendar: Calendar = .current
    ) -> MealVerdict {
        let safeKcal = max(0, cumulativeKcal)
        let kind = config.mealKind(at: date, calendar: calendar)

        // 新用户/无档案：放过校验，按加餐走
        guard let profile = profile else {
            return .snack(kcal: safeKcal)
        }

        // 加餐：先消耗每日缓冲，超过缓冲的新增部分才进入磨平任务。
        guard kind.isRegularMeal else {
            let buffer = config.snackBufferCalories(tdee: profile.tdee)
            guard buffer > 0 else {
                return .snack(kcal: safeKcal)
            }
            let previous = max(0, previousCumulativeKcal)
            let previousGap = max(0, previous - buffer)
            let totalGap = max(0, safeKcal - buffer)
            let incrementalGap = max(0, totalGap - previousGap)
            guard incrementalGap > 0 else {
                return .bufferedSnack(actualCalories: safeKcal, bufferCalories: buffer)
            }
            return .overSnack(actualCalories: safeKcal, bufferCalories: buffer, gap: incrementalGap)
        }

        let quota = config.quotaCalories(for: kind, tdee: profile.tdee)
        // quota 异常（0 或负）兜底：当作加餐处理，不阻断流程
        guard quota > 0 else {
            return .snack(kcal: safeKcal)
        }

        let tolerance = max(0.0, config.toleranceRatio)
        let upper = Int(Double(quota) * (1.0 + tolerance))
        let lower = Int(Double(quota) * (1.0 - tolerance))

        if safeKcal > upper {
            let previous = max(0, previousCumulativeKcal)
            let previousGap = max(0, previous - upper)
            let incrementalGap = max(0, safeKcal - upper - previousGap)
            return .overMeal(
                kind: kind,
                actualCalories: safeKcal,
                quotaCalories: quota,
                gap: incrementalGap
            )
        } else if safeKcal < lower {
            return .underMeal(
                kind: kind,
                actualCalories: safeKcal,
                quotaCalories: quota,
                deficit: lower - safeKcal
            )
        } else {
            return .normalMeal(
                kind: kind,
                actualCalories: safeKcal,
                quotaCalories: quota
            )
        }
    }
}
