import Foundation

/// 把零散的摄入记录按"餐次 + 日历日"聚合，给 MealClassifier 喂累计 kcal 用。
public enum MealIntakeAggregator {

    /// 同一餐次窗口、同一日历日的摄入卡路里求和。
    /// 不读 SwiftData，调用方负责传入待聚合数组。
    /// - Parameters:
    ///   - kind: 目标餐次（snack 也可聚合，但语义弱）
    ///   - intakes: 已记录的摄入数组（通常是当日全部）
    ///   - referenceDate: 用于确定"哪一天"，通常传 Date()（本张照片的拍照时间）
    ///   - calendar: 日历，便于测试注入
    public static func cumulativeKcal(
        kind: MealKind,
        from intakes: [MealIntake],
        on referenceDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        intakes
            .filter { $0.mealKind == kind && calendar.isDate($0.takenAt, inSameDayAs: referenceDate) }
            .reduce(0) { acc, intake in
                acc + max(0, intake.estimatedCalories)
            }
    }

    /// 当日全部摄入卡路里（不限餐次），用于 HomeView 的"今日摄入"统计。
    public static func dailyTotalKcal(
        from intakes: [MealIntake],
        on referenceDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        intakes
            .filter { calendar.isDate($0.takenAt, inSameDayAs: referenceDate) }
            .reduce(0) { acc, intake in
                acc + max(0, intake.estimatedCalories)
            }
    }

    /// 当日指定餐次摄入卡路里，用于加餐缓冲、餐次复盘等轻量账本展示。
    public static func dailyTotalKcal(
        kind: MealKind,
        from intakes: [MealIntake],
        on referenceDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        intakes
            .filter { $0.mealKind == kind && calendar.isDate($0.takenAt, inSameDayAs: referenceDate) }
            .reduce(0) { acc, intake in
                acc + max(0, intake.estimatedCalories)
            }
    }
}
