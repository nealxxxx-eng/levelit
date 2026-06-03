import SwiftUI
import LevelItShared

/// 全局导航路由
enum AppRoute: Hashable {
    case scan
    case manualSelect
    case analysis(FoodAnalysisResult)
    case mealOverConfirm(
        result: FoodAnalysisResult,
        mealKind: MealKind,
        actualKcal: Int,
        gapKcal: Int,
        accumulatedBefore: Int,
        intakeId: String?
    )
    case taskMode(result: FoodAnalysisResult, intakeId: String?)
    case taskCreated(DebtTask)    // 新: "已发送到手表"引导页
    case taskDetail(DebtTask)     // 新: 智能分流 (监控/引导/降级/结果)
    case progress(DebtTask)       // 降级模拟模式 (无 Watch)
    case result(DebtTask)
    case share(DebtTask)
    case taskList
    case foodWall
    case foodDetail(MealIntake)
    case workoutImport
    case stats
    case today
    case settings
    case mealQuotaConfig
    case mealIntakeEdit(MealIntake)
    case anomalyLogForm(date: Date)
    case anomalyLogList
}

/// 食物分析结果 (拍照或手动选择的输出)
struct FoodAnalysisResult: Hashable {
    let foodName: String
    let foodEmoji: String
    let estimatedCalories: Int
    let imageData: Data?

    func hash(into hasher: inout Hasher) {
        hasher.combine(foodName)
        hasher.combine(estimatedCalories)
    }

    static func == (lhs: FoodAnalysisResult, rhs: FoodAnalysisResult) -> Bool {
        lhs.foodName == rhs.foodName && lhs.estimatedCalories == rhs.estimatedCalories
    }
}
