import Testing
import Foundation
@testable import LevelItShared

@Suite("MealIntakeAggregator Tests")
struct MealIntakeAggregatorTests {

    private func date(year: Int = 2026, month: Int = 5, day: Int = 10, hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func intake(
        kcal: Int,
        kind: MealKind,
        at: Date,
        verdict: MealVerdictKind = .normal
    ) -> MealIntake {
        MealIntake(
            foodName: "test",
            foodEmoji: "🍽️",
            estimatedCalories: kcal,
            originalCalories: kcal,
            takenAt: at,
            mealKind: kind,
            verdictKind: verdict
        )
    }

    // MARK: - cumulativeKcal

    @Test("空数组返回 0")
    func emptyReturnsZero() {
        #expect(MealIntakeAggregator.cumulativeKcal(
            kind: .lunch, from: [], on: date(hour: 12)
        ) == 0)
    }

    @Test("同餐窗口同日多张照片累加")
    func sameMealSameDayAccumulates() {
        let today = date(hour: 12)
        let intakes = [
            intake(kcal: 200, kind: .lunch, at: date(hour: 12, minute: 5)),
            intake(kcal: 150, kind: .lunch, at: date(hour: 12, minute: 30)),
            intake(kcal: 100, kind: .lunch, at: date(hour: 13)),
        ]
        let total = MealIntakeAggregator.cumulativeKcal(
            kind: .lunch, from: intakes, on: today
        )
        #expect(total == 450)
    }

    @Test("不同 mealKind 不混")
    func differentKindsDontMix() {
        let today = date(hour: 12)
        let intakes = [
            intake(kcal: 200, kind: .lunch,     at: date(hour: 12)),
            intake(kcal: 100, kind: .breakfast, at: date(hour: 8)),
            intake(kcal: 50,  kind: .snack,     at: date(hour: 15)),
        ]
        #expect(MealIntakeAggregator.cumulativeKcal(
            kind: .lunch, from: intakes, on: today
        ) == 200)
        #expect(MealIntakeAggregator.cumulativeKcal(
            kind: .breakfast, from: intakes, on: today
        ) == 100)
        #expect(MealIntakeAggregator.cumulativeKcal(
            kind: .snack, from: intakes, on: today
        ) == 50)
    }

    @Test("跨日不累加（昨天的午餐不计入今天）")
    func differentDaysExcluded() {
        let today = date(day: 10, hour: 12)
        let intakes = [
            intake(kcal: 999, kind: .lunch, at: date(day: 9, hour: 12)),
            intake(kcal: 200, kind: .lunch, at: date(day: 10, hour: 12)),
            intake(kcal: 999, kind: .lunch, at: date(day: 11, hour: 12)),
        ]
        let total = MealIntakeAggregator.cumulativeKcal(
            kind: .lunch, from: intakes, on: today
        )
        #expect(total == 200)
    }

    @Test("负 kcal 钳到 0（防御性，理论不该出现）")
    func negativeKcalClamped() {
        let today = date(hour: 12)
        let intakes = [
            intake(kcal: 100, kind: .lunch, at: date(hour: 12)),
            intake(kcal: -50, kind: .lunch, at: date(hour: 12, minute: 30)),
        ]
        #expect(MealIntakeAggregator.cumulativeKcal(
            kind: .lunch, from: intakes, on: today
        ) == 100)
    }

    // MARK: - dailyTotalKcal

    @Test("当日总摄入：所有 mealKind 都加")
    func dailyTotalSumsAllKinds() {
        let today = date(hour: 20)
        let intakes = [
            intake(kcal: 300, kind: .breakfast, at: date(hour: 8)),
            intake(kcal: 600, kind: .lunch,     at: date(hour: 12)),
            intake(kcal: 500, kind: .dinner,    at: date(hour: 18)),
            intake(kcal: 100, kind: .snack,     at: date(hour: 15)),
        ]
        #expect(MealIntakeAggregator.dailyTotalKcal(
            from: intakes, on: today
        ) == 1500)
    }

    @Test("当日总摄入：跨日不计入")
    func dailyTotalExcludesOtherDays() {
        let today = date(day: 10, hour: 20)
        let intakes = [
            intake(kcal: 999, kind: .lunch, at: date(day: 9, hour: 12)),
            intake(kcal: 300, kind: .lunch, at: date(day: 10, hour: 12)),
        ]
        #expect(MealIntakeAggregator.dailyTotalKcal(
            from: intakes, on: today
        ) == 300)
    }

    @Test("当日指定餐次摄入：只统计同日同 mealKind")
    func dailyTotalByKindOnlySumsMatchingKind() {
        let today = date(day: 10, hour: 20)
        let intakes = [
            intake(kcal: 120, kind: .snack, at: date(day: 10, hour: 10, minute: 45)),
            intake(kcal: 80, kind: .snack, at: date(day: 10, hour: 15)),
            intake(kcal: 600, kind: .lunch, at: date(day: 10, hour: 12)),
            intake(kcal: 999, kind: .snack, at: date(day: 9, hour: 15)),
        ]

        #expect(MealIntakeAggregator.dailyTotalKcal(
            kind: .snack, from: intakes, on: today
        ) == 200)
    }

    // MARK: - 与 MealClassifier 的集成

    @Test("Aggregator 喂 MealClassifier 累加版本：第三张照片触发 over")
    func feedsClassifierForOverDetection() {
        // sedentary 男 30 170cm 65kg → TDEE=1880, lunch quota=658, upper=723
        let profile = UserProfile(
            gender: .male, age: 30, heightCM: 170, weightKG: 65,
            activityLevel: .sedentary
        )
        let lunchTime = date(hour: 12, minute: 30)
        let intakes = [
            intake(kcal: 300, kind: .lunch, at: date(hour: 12)),
            intake(kcal: 250, kind: .lunch, at: date(hour: 12, minute: 15)),
        ]
        let cumulativeBefore = MealIntakeAggregator.cumulativeKcal(
            kind: .lunch, from: intakes, on: lunchTime
        )
        // 第三张 200 kcal → 累计 750 → > upper 723 → over，gap = 750-723 = 27
        let total = cumulativeBefore + 200
        let v = MealClassifier.classify(
            cumulativeKcal: total,
            at: lunchTime,
            profile: profile
        )
        if case .overMeal(_, let actual, _, let gap) = v {
            #expect(actual == 750)
            #expect(gap == 27)
        } else {
            Issue.record("expected overMeal after cumulative; got \(v)")
        }
    }
}
