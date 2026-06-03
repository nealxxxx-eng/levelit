import Foundation

// MARK: - 餐次配额配置

public enum LevelingStrategy: String, Codable, CaseIterable, Sendable {
    case strict
    case standard
    case relaxed

    public var displayName: String {
        switch self {
        case .strict:   return "严格"
        case .standard: return "标准"
        case .relaxed:  return "轻松"
        }
    }

    public var description: String {
        switch self {
        case .strict:
            return "加餐缓冲较小，更容易生成磨平任务。"
        case .standard:
            return "适合日常使用，饮料小零食先缓冲，高热量再磨平。"
        case .relaxed:
            return "加餐缓冲更宽松，降低任务压力。"
        }
    }

    public var snackBufferRatio: Double {
        switch self {
        case .strict:   return 0.06
        case .standard: return 0.10
        case .relaxed:  return 0.15
        }
    }

    public var maxSnackBufferCalories: Int {
        switch self {
        case .strict:   return 150
        case .standard: return AppConstants.maxDailySnackBuffer
        case .relaxed:  return 350
        }
    }
}

/// 用户可覆写的三餐时间窗口 + 配额比例
///
/// 默认值见 `MealKind.defaultWindows` / `MealKind.defaultQuotaRatio`。
/// 配置以 JSON 形式存于 UserDefaults，未来如需多设备同步，可迁到 CloudKit。
public struct MealQuotaConfig: Codable, Sendable, Equatable {

    /// 三餐 + 加餐的时间窗口（snack 时段在所有正餐窗口之外，因此不需要单独窗口字段）
    public var windows: [MealKind: MealTimeWindow]

    /// 各餐次配额占 TDEE 的比例
    public var ratios: [MealKind: Double]

    /// 偏差容差（默认 ±10%）
    public var toleranceRatio: Double

    /// 磨平任务策略：影响加餐缓冲大小，不改变三餐配额。
    public var levelingStrategy: LevelingStrategy

    public init(
        windows: [MealKind: MealTimeWindow] = MealKind.defaultWindows,
        ratios: [MealKind: Double] = MealKind.defaultQuotaRatio,
        toleranceRatio: Double = 0.10,
        levelingStrategy: LevelingStrategy = .standard
    ) {
        self.windows = windows
        self.ratios = ratios
        self.toleranceRatio = toleranceRatio
        self.levelingStrategy = levelingStrategy
    }

    private enum CodingKeys: String, CodingKey {
        case windows
        case ratios
        case toleranceRatio
        case levelingStrategy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windows = try container.decode([MealKind: MealTimeWindow].self, forKey: .windows)
        ratios = try container.decode([MealKind: Double].self, forKey: .ratios)
        toleranceRatio = try container.decode(Double.self, forKey: .toleranceRatio)
        levelingStrategy = try container.decodeIfPresent(LevelingStrategy.self, forKey: .levelingStrategy) ?? .standard
    }

    /// 默认配置
    public static let `default` = MealQuotaConfig()

    /// 给定 TDEE，计算某餐次的目标卡路里（向下取整）。
    /// 若该餐次无比例（理论不会发生），返回 0。
    public func quotaCalories(for kind: MealKind, tdee: Int) -> Int {
        guard let r = ratios[kind] else { return 0 }
        return Int(Double(tdee) * r)
    }

    /// 每日加餐缓冲额度。默认使用 snack ratio，并限制最高值，避免 TDEE 高时放大零食预算。
    public func snackBufferCalories(tdee: Int) -> Int {
        let quota = Int(Double(tdee) * levelingStrategy.snackBufferRatio)
        return max(0, min(quota, levelingStrategy.maxSnackBufferCalories))
    }

    /// 判断 date 落在哪个正餐窗口；落在所有正餐窗口之外即为 snack。
    public func mealKind(at date: Date, calendar: Calendar = .current) -> MealKind {
        for kind in [MealKind.breakfast, .lunch, .dinner] {
            if let w = windows[kind], w.contains(date, calendar: calendar) {
                return kind
            }
        }
        return .snack
    }
}

// MARK: - 持久化

public enum MealQuotaConfigStore {
    private static let key = "mealQuotaConfig_v1"

    public static var current: MealQuotaConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(MealQuotaConfig.self, from: data)
        else {
            return .default
        }
        return cfg
    }

    public static func save(_ config: MealQuotaConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Dictionary<MealKind, ...> Codable 桥接
//
// Swift 的 Codable 默认要求 Dictionary 的 Key 是 String/Int；
// MealKind 是 RawRepresentable<String> 的枚举，已自动满足，无需额外实现。
