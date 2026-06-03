import Testing
import Foundation
@testable import LevelItShared

@Suite("MealClassifier Tests")
struct MealClassifierTests {

    // MARK: - 测试夹具

    /// sedentary 男 30 岁 170cm 65kg
    /// BMR = 10*65 + 6.25*170 - 5*30 + 5 = 1567
    /// TDEE = 1567 * 1.2 = 1880
    /// breakfast 25% = 470 / lunch 35% = 658 / dinner 30% = 564
    /// lunch ±10% 区间 = [592, 723]
    private let profile = UserProfile(
        gender: .male,
        age: 30,
        heightCM: 170,
        weightKG: 65,
        activityLevel: .sedentary
    )

    private let config = MealQuotaConfig.default

    /// 构造一个本地时区下指定 hour:minute 的 Date（日期任选 2026-05-09）
    private func date(at hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 9
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    // MARK: - 时间窗 → 餐次

    @Test("06:00 → 早餐窗")
    func breakfastWindowStart() {
        let v = MealClassifier.classify(kcal: 0, at: date(at: 6, 0), profile: profile)
        if case .underMeal(let kind, _, _, _) = v {
            #expect(kind == .breakfast)
        } else {
            Issue.record("expected underMeal at breakfast, got \(v)")
        }
    }

    @Test("10:30 边界 → 加餐（右开区间）")
    func breakfastWindowEnd() {
        let v = MealClassifier.classify(kcal: 100, at: date(at: 10, 30), profile: profile)
        if case .bufferedSnack(let actual, let buffer) = v {
            #expect(actual == 100)
            #expect(buffer == 188)
        } else {
            Issue.record("expected bufferedSnack at 10:30, got \(v)")
        }
    }

    @Test("10:29 仍属早餐（验证拓宽后的右边界）")
    func breakfastWindowJustBeforeEnd() {
        let v = MealClassifier.classify(kcal: 100, at: date(at: 10, 29), profile: profile)
        switch v {
        case .normalMeal(let kind, _, _),
             .overMeal(let kind, _, _, _),
             .underMeal(let kind, _, _, _):
            #expect(kind == .breakfast)
        case .snack, .bufferedSnack, .overSnack:
            Issue.record("10:29 should still be breakfast, got snack")
        }
    }

    @Test("12:00 → 午餐窗")
    func lunchWindow() {
        let v = MealClassifier.classify(kcal: 600, at: date(at: 12, 0), profile: profile)
        if case .normalMeal(let kind, _, _) = v {
            #expect(kind == .lunch)
        } else {
            Issue.record("expected normalMeal at lunch, got \(v)")
        }
    }

    @Test("15:00 不在任何正餐窗口 → 加餐")
    func snackBetweenMeals() {
        let v = MealClassifier.classify(kcal: 100, at: date(at: 15, 0), profile: profile)
        if case .bufferedSnack(let actual, let buffer) = v {
            #expect(actual == 100)
            #expect(buffer == 188)
        } else {
            Issue.record("expected bufferedSnack, got \(v)")
        }
    }

    // MARK: - 偏差判断（午餐 quota≈624, ±10% → [561, 686]）

    @Test("午餐 600 kcal 在 ±10% 内 → normalMeal")
    func lunchWithinTolerance() {
        let v = MealClassifier.classify(kcal: 600, at: date(at: 12, 0), profile: profile)
        guard case .normalMeal(let kind, let actual, let quota) = v else {
            Issue.record("expected normalMeal, got \(v)"); return
        }
        #expect(kind == .lunch)
        #expect(actual == 600)
        #expect(quota == 658)  // floor(1880 * 0.35) = 658
    }

    @Test("午餐 800 kcal 超出上界 → overMeal，gap = 800 - 723 = 77")
    func lunchOver() {
        let v = MealClassifier.classify(kcal: 800, at: date(at: 12, 30), profile: profile)
        guard case .overMeal(_, _, let quota, let gap) = v else {
            Issue.record("expected overMeal, got \(v)"); return
        }
        #expect(quota == 658)
        // upper = floor(658 * 1.10) = 723，gap = 800 - 723 = 77
        #expect(gap == 77)
    }

    @Test("overMeal 必须进磨平任务，taskCalories == gap")
    func overMealTriggersTask() {
        let v = MealClassifier.classify(kcal: 1000, at: date(at: 12, 0), profile: profile)
        #expect(v.shouldCreateTask == true)
        if case .overMeal(_, _, _, let gap) = v {
            #expect(v.taskCalories == gap)
        } else {
            Issue.record("expected overMeal")
        }
    }

    @Test("normalMeal 不进磨平任务")
    func normalMealNoTask() {
        let v = MealClassifier.classify(kcal: 600, at: date(at: 12, 0), profile: profile)
        #expect(v.shouldCreateTask == false)
        #expect(v.taskCalories == 0)
    }

    @Test("underMeal 不进磨平任务（吃得少不还债）")
    func underMealNoTask() {
        let v = MealClassifier.classify(kcal: 100, at: date(at: 12, 0), profile: profile)
        if case .underMeal(_, _, _, let deficit) = v {
            #expect(deficit > 0)
            #expect(v.shouldCreateTask == false)
        } else {
            Issue.record("expected underMeal")
        }
    }

    @Test("snack 先消耗每日缓冲，只对超额部分进磨平任务")
    func snackUsesDailyBufferBeforeTask() {
        let v = MealClassifier.classify(kcal: 350, at: date(at: 15, 0), profile: profile)
        #expect(v.shouldCreateTask == true)
        #expect(v.taskCalories == 162)
        if case .overSnack(let actual, let buffer, let gap) = v {
            #expect(actual == 350)
            #expect(buffer == 188)
            #expect(gap == 162)
        } else {
            Issue.record("expected overSnack")
        }
    }

    @Test("snack 累加时不重复计算已被缓冲覆盖的部分")
    func snackCumulativeOnlyCreatesIncrementalGap() {
        let v = MealClassifier.classify(
            cumulativeKcal: 230,
            previousCumulativeKcal: 180,
            at: date(at: 15),
            profile: profile
        )
        #expect(v.shouldCreateTask == true)
        #expect(v.taskCalories == 42)
        if case .overSnack(_, let buffer, let gap) = v {
            #expect(buffer == 188)
            #expect(gap == 42)
        } else {
            Issue.record("expected overSnack")
        }
    }

    // MARK: - 边界

    @Test("nil profile → 一律 snack（新用户兜底）")
    func nilProfileFallsBackToSnack() {
        let v = MealClassifier.classify(kcal: 500, at: date(at: 12, 0), profile: nil)
        if case .snack(let k) = v {
            #expect(k == 500)
        } else {
            Issue.record("expected snack for nil profile")
        }
    }

    @Test("负卡路里钳到 0")
    func negativeKcalClampedToZero() {
        let v = MealClassifier.classify(kcal: -50, at: date(at: 12, 0), profile: profile)
        if case .underMeal(_, let actual, _, _) = v {
            #expect(actual == 0)
        } else {
            Issue.record("expected underMeal with 0 actual, got \(v)")
        }
    }

    @Test("0 容差：精准匹配 quota → normalMeal，差 1 → over/under")
    func zeroToleranceBoundary() {
        let cfg0 = MealQuotaConfig(toleranceRatio: 0)
        // lunch quota = 658
        let exact = MealClassifier.classify(kcal: 658, at: date(at: 12), profile: profile, config: cfg0)
        if case .normalMeal = exact { /* ok */ } else { Issue.record("expected normalMeal at exact quota") }

        let over = MealClassifier.classify(kcal: 659, at: date(at: 12), profile: profile, config: cfg0)
        if case .overMeal(_, _, _, let gap) = over {
            #expect(gap == 1)
        } else { Issue.record("expected overMeal with gap=1") }
    }

    // MARK: - 累加版本

    // MARK: - 回归测试：09:40 / 280 kcal 不再被判为加餐
    //
    // 历史 bug：默认窗口 06:00-09:30 太严，导致 09:40 拍的早餐被判成加餐进了磨平任务。
    // 修复：默认窗口拓宽到 06:00-10:30。

    @Test("REGRESSION: 09:40 拍 280 kcal 默认窗口下被识别为早餐（不进任务）")
    func regression_breakfastWindowCovers0940() {
        let v = MealClassifier.classify(kcal: 280, at: date(at: 9, 40), profile: profile)
        // breakfast quota = floor(1880 * 0.25) = 470，±10% [423, 517]
        // 280 < 423 → underMeal（提示但不进任务）
        if case .underMeal(let kind, _, _, _) = v {
            #expect(kind == .breakfast)
            #expect(v.shouldCreateTask == false)
        } else {
            Issue.record("expected underMeal breakfast (default窗口已含 09:40); got \(v)")
        }
    }

    @Test("累加版本：同餐两张照片合计超标")
    func cumulativeOver() {
        // lunch upper = 723，先 400 + 后 400 = 800（累计），第二张应判定 overMeal gap=77
        let v = MealClassifier.classify(cumulativeKcal: 800, at: date(at: 12, 30), profile: profile)
        if case .overMeal(_, let actual, _, let gap) = v {
            #expect(actual == 800)
            #expect(gap == 77)
        } else { Issue.record("expected overMeal cumulative") }
    }
}
