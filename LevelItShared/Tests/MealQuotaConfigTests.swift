import Testing
import Foundation
@testable import LevelItShared

@Suite("MealQuotaConfig Tests")
struct MealQuotaConfigTests {

    private func date(at hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 10
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    // MARK: - 默认值

    @Test("默认配置：三餐 + 加餐比例总和 = 100%")
    func defaultRatiosSumTo100() {
        let cfg = MealQuotaConfig.default
        let b: Double = cfg.ratios[.breakfast] ?? 0
        let l: Double = cfg.ratios[.lunch] ?? 0
        let d: Double = cfg.ratios[.dinner] ?? 0
        let s: Double = cfg.ratios[.snack] ?? 0
        let sum = b + l + d + s
        #expect(abs(sum - 1.0) < 0.0001)
    }

    @Test("默认容差 = 10%")
    func defaultTolerance() {
        #expect(MealQuotaConfig.default.toleranceRatio == 0.10)
    }

    // MARK: - quota 计算

    @Test("TDEE 2000，午餐 35% → 700 kcal")
    func quotaCalculation() {
        let q = MealQuotaConfig.default.quotaCalories(for: .lunch, tdee: 2000)
        #expect(q == 700)
    }

    @Test("TDEE 0 → 配额 0（不崩）")
    func quotaWithZeroTDEE() {
        #expect(MealQuotaConfig.default.quotaCalories(for: .breakfast, tdee: 0) == 0)
    }

    @Test("加餐缓冲使用 snack ratio，且最高封顶")
    func snackBufferUsesSnackRatioAndCaps() {
        let cfg = MealQuotaConfig.default

        #expect(cfg.snackBufferCalories(tdee: 2000) == 200)
        #expect(cfg.snackBufferCalories(tdee: 4000) == AppConstants.maxDailySnackBuffer)
        #expect(cfg.snackBufferCalories(tdee: 0) == 0)
    }

    @Test("不同磨平策略对应不同加餐缓冲")
    func levelingStrategyControlsSnackBuffer() {
        let strict = MealQuotaConfig(levelingStrategy: .strict)
        let standard = MealQuotaConfig(levelingStrategy: .standard)
        let relaxed = MealQuotaConfig(levelingStrategy: .relaxed)

        #expect(strict.snackBufferCalories(tdee: 2000) == 120)
        #expect(standard.snackBufferCalories(tdee: 2000) == 200)
        #expect(relaxed.snackBufferCalories(tdee: 2000) == 300)
        #expect(relaxed.snackBufferCalories(tdee: 4000) == LevelingStrategy.relaxed.maxSnackBufferCalories)
    }

    // MARK: - mealKind(at:)

    @Test("07:00 → breakfast")
    func sevenIsBreakfast() {
        #expect(MealQuotaConfig.default.mealKind(at: date(at: 7)) == .breakfast)
    }

    @Test("12:30 → lunch")
    func noonIsLunch() {
        #expect(MealQuotaConfig.default.mealKind(at: date(at: 12, 30)) == .lunch)
    }

    @Test("18:00 → dinner")
    func eveningIsDinner() {
        #expect(MealQuotaConfig.default.mealKind(at: date(at: 18)) == .dinner)
    }

    @Test("22:00 → snack（深夜）")
    func lateNightIsSnack() {
        #expect(MealQuotaConfig.default.mealKind(at: date(at: 22)) == .snack)
    }

    @Test("10:00 → breakfast（默认窗口已拓宽至 10:30）")
    func tenAMIsBreakfast() {
        #expect(MealQuotaConfig.default.mealKind(at: date(at: 10)) == .breakfast)
    }

    @Test("10:30 边界（右开）→ snack")
    func breakfastEndIsSnack() {
        #expect(MealQuotaConfig.default.mealKind(at: date(at: 10, 30)) == .snack)
    }

    @Test("14:00 边界（右开）→ snack")
    func lunchEndIsSnack() {
        #expect(MealQuotaConfig.default.mealKind(at: date(at: 14, 0)) == .snack)
    }

    // MARK: - 持久化（隔离 UserDefaults）

    @Test("save → current 读回一致；reset 后回到 default")
    func saveLoadReset() {
        // 备份 + 清理
        let suiteKey = "mealQuotaConfig_v1"
        let backup = UserDefaults.standard.data(forKey: suiteKey)
        defer {
            if let backup = backup {
                UserDefaults.standard.set(backup, forKey: suiteKey)
            } else {
                UserDefaults.standard.removeObject(forKey: suiteKey)
            }
        }

        var cfg = MealQuotaConfig.default
        cfg.toleranceRatio = 0.20
        cfg.ratios[.lunch] = 0.40
        MealQuotaConfigStore.save(cfg)

        let loaded = MealQuotaConfigStore.current
        #expect(loaded.toleranceRatio == 0.20)
        #expect(loaded.ratios[.lunch] == 0.40)

        MealQuotaConfigStore.reset()
        #expect(MealQuotaConfigStore.current.toleranceRatio == 0.10)
    }

    @Test("旧版 JSON 缺少 levelingStrategy 时默认 standard")
    func legacyJSONDefaultsStrategyToStandard() throws {
        let data = try JSONEncoder().encode(MealQuotaConfig.default)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "levelingStrategy")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(MealQuotaConfig.self, from: legacyData)

        #expect(decoded.levelingStrategy == .standard)
        #expect(decoded.snackBufferCalories(tdee: 2000) == 200)
    }
}
