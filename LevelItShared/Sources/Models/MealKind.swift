import Foundation

// MARK: - 餐次类型

/// 餐次分类：三正餐 + 加餐
public enum MealKind: String, Codable, CaseIterable, Sendable, Identifiable {
    public var id: String { rawValue }

    case breakfast
    case lunch
    case dinner
    case snack

    public var displayName: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch:     return "午餐"
        case .dinner:    return "晚餐"
        case .snack:     return "加餐"
        }
    }

    public var emoji: String {
        switch self {
        case .breakfast: return "🌅"
        case .lunch:     return "☀️"
        case .dinner:    return "🌙"
        case .snack:     return "🍪"
        }
    }

    /// 是否为正餐（参与配额校验）
    public var isRegularMeal: Bool {
        self != .snack
    }
}

// MARK: - 餐次时间窗口

/// 一餐的时间窗口；用本地时间的 (hour, minute) 表示
public struct MealTimeWindow: Codable, Sendable, Equatable {
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int

    public init(startHour: Int, startMinute: Int = 0, endHour: Int, endMinute: Int = 0) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    /// 起始分钟数（00:00 起算）
    public var startMinutes: Int { startHour * 60 + startMinute }

    /// 结束分钟数（00:00 起算）
    public var endMinutes: Int { endHour * 60 + endMinute }

    /// 给定本地日历下，date 的分钟数是否落在窗口内（左闭右开）
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let m = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return m >= startMinutes && m < endMinutes
    }
}

// MARK: - 默认值

public extension MealKind {
    /// 默认时间窗口（产品默认值；用户可在 MealQuotaConfig 中覆写）
    /// 取宽松值贴近真实生活习惯，避免"10 点的早餐被算成加餐"这类困扰。
    static let defaultWindows: [MealKind: MealTimeWindow] = [
        .breakfast: MealTimeWindow(startHour: 6,  startMinute: 0,  endHour: 10, endMinute: 30),
        .lunch:     MealTimeWindow(startHour: 11, startMinute: 0,  endHour: 14, endMinute: 0),
        .dinner:    MealTimeWindow(startHour: 17, startMinute: 0,  endHour: 20, endMinute: 30),
    ]

    /// 默认占 TDEE 的比例（snack 不参与正餐校验，给一个加餐总额上限做参考）
    static let defaultQuotaRatio: [MealKind: Double] = [
        .breakfast: 0.25,
        .lunch:     0.35,
        .dinner:    0.30,
        .snack:     0.10,
    ]
}
