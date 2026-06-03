import Foundation

// MARK: - 性别

public enum Gender: String, Codable, CaseIterable, Sendable {
    case male
    case female

    public var displayName: String {
        switch self {
        case .male:   return "男"
        case .female: return "女"
        }
    }
}

// MARK: - 活动水平

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary  // 久坐/办公
    case light      // 轻度运动 (每周1-3次)
    case moderate   // 中度运动 (每周3-5次)
    case active     // 重度运动 (每周6-7次或体力劳动)

    public var displayName: String {
        switch self {
        case .sedentary: return "久坐办公"
        case .light:     return "轻度运动"
        case .moderate:  return "中度运动"
        case .active:    return "高强度运动"
        }
    }

    public var description: String {
        switch self {
        case .sedentary: return "几乎不运动，长时间坐着"
        case .light:     return "每周运动 1-3 次，日常步行"
        case .moderate:  return "每周运动 3-5 次"
        case .active:    return "每周 6-7 次或体力劳动"
        }
    }

    /// 自然余额系数 (基于 BMR 的百分比)
    public var allowanceRate: Double {
        switch self {
        case .sedentary: return 0.07   // 7%
        case .light:     return 0.10   // 10%
        case .moderate:  return 0.13   // 13%
        case .active:    return 0.16   // 16%
        }
    }

    /// TDEE 活动系数（业内通用 Mifflin-St Jeor 系数）
    /// 用于估算每日总能量消耗 = BMR × tdeeMultiplier，作为每日摄入目标的基准。
    public var tdeeMultiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light:     return 1.375
        case .moderate:  return 1.55
        case .active:    return 1.725
        }
    }
}

// MARK: - 用户档案

public struct UserProfile: Codable, Sendable, Equatable {
    public var gender: Gender
    public var age: Int
    public var heightCM: Int
    public var weightKG: Double
    public var activityLevel: ActivityLevel
    /// 后台大模型估算的每日总能量消耗。为空时使用本地 Mifflin-St Jeor 公式。
    public var aiEstimatedTDEE: Int?
    public var aiEstimateSummary: String?
    public var aiEstimateUpdatedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        gender: Gender,
        age: Int,
        heightCM: Int,
        weightKG: Double,
        activityLevel: ActivityLevel,
        aiEstimatedTDEE: Int? = nil,
        aiEstimateSummary: String? = nil,
        aiEstimateUpdatedAt: Date? = nil
    ) {
        self.gender = gender
        self.age = age
        self.heightCM = heightCM
        self.weightKG = weightKG
        self.activityLevel = activityLevel
        self.aiEstimatedTDEE = aiEstimatedTDEE
        self.aiEstimateSummary = aiEstimateSummary
        self.aiEstimateUpdatedAt = aiEstimateUpdatedAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 基础代谢率 (Mifflin-St Jeor 公式, kcal/天)
    public var bmr: Int {
        let base = 10.0 * weightKG + 6.25 * Double(heightCM) - 5.0 * Double(age)
        switch gender {
        case .male:   return Int(base + 5)
        case .female: return Int(base - 161)
        }
    }

    /// 每日自然消耗余额 (kcal)
    /// 代表身体在三餐之外通过基础代谢自然消耗的额外热量
    public var dailyAllowance: Int {
        Int(Double(bmr) * activityLevel.allowanceRate)
    }

    /// 本地公式估算的每日总能量消耗 (kcal/天)
    public var formulaTDEE: Int {
        Int(Double(bmr) * activityLevel.tdeeMultiplier)
    }

    /// 每日总能量消耗 (kcal/天)，作为正餐配额的基准
    public var tdee: Int {
        if let aiEstimatedTDEE,
           AppConstants.ProfileDefaults.minDailyEnergyEstimate...AppConstants.ProfileDefaults.maxDailyEnergyEstimate ~= aiEstimatedTDEE {
            return aiEstimatedTDEE
        }
        return formulaTDEE
    }
}

// MARK: - 本地持久化 (UserDefaults)

public enum UserProfileStore {
    private static let key = "userProfile_v1"

    public static var current: UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else { return nil }
        return profile
    }

    public static var isRegistered: Bool {
        current != nil
    }

    public static func save(_ profile: UserProfile) {
        var p = profile
        p.updatedAt = Date()
        guard let data = try? JSONEncoder().encode(p) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - 每日自然余额追踪 (UserDefaults, 按日重置)

public enum NaturalAllowance {
    private static let usedKey = "naturalAllowance_used"
    private static let dateKey = "naturalAllowance_date"

    /// 今日总额度
    public static var dailyTotal: Int {
        UserProfileStore.current?.dailyAllowance ?? 0
    }

    /// 今日已消耗额度
    public static var usedToday: Int {
        guard isToday else { return 0 }
        return UserDefaults.standard.integer(forKey: usedKey)
    }

    /// 今日剩余可用额度
    public static var available: Int {
        max(0, dailyTotal - usedToday)
    }

    /// 消耗自然余额, 返回实际消耗量
    public static func consume(_ amount: Int) -> Int {
        ensureToday()
        let consumed = min(amount, available)
        guard consumed > 0 else { return 0 }
        UserDefaults.standard.set(usedToday + consumed, forKey: usedKey)
        return consumed
    }

    /// 回滚消耗 (用于事务失败回滚)
    public static func rollback(_ amount: Int) {
        guard isToday else { return }
        let newUsed = max(0, UserDefaults.standard.integer(forKey: usedKey) - amount)
        UserDefaults.standard.set(newUsed, forKey: usedKey)
    }

    private static var isToday: Bool {
        guard let stored = UserDefaults.standard.string(forKey: dateKey) else { return false }
        return stored == todayString
    }

    private static func ensureToday() {
        if !isToday {
            UserDefaults.standard.set(0, forKey: usedKey)
            UserDefaults.standard.set(todayString, forKey: dateKey)
        }
    }

    private static var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
