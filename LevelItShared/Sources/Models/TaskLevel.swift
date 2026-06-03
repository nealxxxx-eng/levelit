import Foundation
import SwiftUI

/// 任务等级 — 按热量分 4 档, 对应颜色
public enum TaskLevel: String, Codable, CaseIterable, Sendable {
    case green   // < 120 kcal
    case yellow  // 120 - 219 kcal
    case orange  // 220 - 349 kcal
    case red     // >= 350 kcal

    /// 根据热量自动判定等级
    public static func from(calories: Int) -> TaskLevel {
        switch calories {
        case ..<120:    return .green
        case 120..<220: return .yellow
        case 220..<350: return .orange
        default:        return .red
        }
    }

    /// 对应的显示颜色
    public var color: Color {
        switch self {
        case .green:  return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red:    return .red
        }
    }

    /// 中文显示名
    public var displayName: String {
        switch self {
        case .green:  return "轻松"
        case .yellow: return "适中"
        case .orange: return "挑战"
        case .red:    return "硬核"
        }
    }
}
