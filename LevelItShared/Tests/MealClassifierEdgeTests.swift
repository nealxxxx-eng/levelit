import Testing
import Foundation
@testable import LevelItShared

@Suite("餐次边缘提示")
struct MealClassifierEdgeTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ h: Int, _ m: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 18
        comps.hour = h; comps.minute = m
        return cal.date(from: comps)!
    }

    private let config = MealQuotaConfig(windows: [
        .breakfast: MealTimeWindow(startHour: 6,  startMinute: 0, endHour: 10, endMinute: 30),
        .lunch:     MealTimeWindow(startHour: 11, startMinute: 0, endHour: 14, endMinute: 0),
        .dinner:    MealTimeWindow(startHour: 17, startMinute: 0, endHour: 20, endMinute: 30),
    ])

    private var profile: UserProfile {
        UserProfile(gender: .male, age: 30, heightCM: 170, weightKG: 65, activityLevel: .light)
    }

    // MARK: - edgeSuggestion

    @Test("窗口正中不提示")
    func centerNoSuggestion() {
        #expect(MealClassifier.edgeSuggestion(at: at(12, 30), config: config, calendar: cal) == nil)
    }

    @Test("窗口尾边内侧 ±30 提示该正餐")
    func innerEdge() {
        #expect(MealClassifier.edgeSuggestion(at: at(13, 45), config: config, calendar: cal) == .lunch)
    }

    @Test("窗口尾边外侧 ±30 提示该正餐")
    func outerEdge() {
        #expect(MealClassifier.edgeSuggestion(at: at(14, 20), config: config, calendar: cal) == .lunch)
    }

    @Test("正好在边界 30 分钟处仍提示（闭区间）")
    func exactlyAtThreshold() {
        #expect(MealClassifier.edgeSuggestion(at: at(14, 30), config: config, calendar: cal) == .lunch)
        #expect(MealClassifier.edgeSuggestion(at: at(14, 31), config: config, calendar: cal) == nil)
    }

    @Test("远离任何边界不提示")
    func farFromEdge() {
        #expect(MealClassifier.edgeSuggestion(at: at(3, 0), config: config, calendar: cal) == nil)
    }

    // MARK: - overrideKind 透传

    @Test("override 为加餐时走加餐分支")
    func overrideSnack() {
        let v = MealClassifier.classify(kcal: 75, at: at(12, 0), profile: profile,
                                        config: config, calendar: cal, overrideKind: .snack)
        switch v {
        case .snack, .bufferedSnack, .overSnack: break  // 加餐族任一即可
        default: Issue.record("override .snack 应走加餐分支，实际 \(v)")
        }
    }

    @Test("override 为正餐且达标时 normalMeal（即便时间本属加餐时段）")
    func overrideNormalMeal() {
        let quota = config.quotaCalories(for: .lunch, tdee: profile.tdee)
        // 03:00 本应是加餐时段，但 override .lunch 后按午餐配额判定
        let v = MealClassifier.classify(kcal: quota, at: at(3, 0), profile: profile,
                                        config: config, calendar: cal, overrideKind: .lunch)
        if case .normalMeal(let kind, _, _) = v {
            #expect(kind == .lunch)
        } else {
            Issue.record("应为 normalMeal(.lunch)，实际 \(v)")
        }
    }
}
