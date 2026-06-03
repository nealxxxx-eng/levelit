import Foundation

/// 任务来源 — 区分 iPhone 创建还是 Watch 独立创建
public enum TaskSource: String, Codable, CaseIterable, Sendable {
    case iPhone
    case watch
}
