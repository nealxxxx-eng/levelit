import Foundation

/// 债务类型 — MVP 仅支持 food, 未来扩展 alcohol/sedentary/sleep
public enum DebtType: String, Codable, CaseIterable, Sendable {
    case food
    // 未来扩展:
    // case alcohol
    // case sedentary
    // case sleep
}
