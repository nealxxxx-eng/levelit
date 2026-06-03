import Foundation

/// 预置食物分类
public enum FoodCategory: String, Codable, CaseIterable, Sendable {
    case milkTea   = "奶茶"
    case snack     = "零食"
    case fastFood  = "快餐"
    case drink     = "饮料"
    case dessert   = "甜品"
    case coffee    = "咖啡"
}

/// 预置食物 — 纯值类型, 不需要持久化
public struct PresetFood: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let emoji: String
    public let category: FoodCategory
    public let estimatedCalories: Int

    public init(id: String = UUID().uuidString, name: String, emoji: String, category: FoodCategory, estimatedCalories: Int) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.category = category
        self.estimatedCalories = estimatedCalories
    }
}
