import Foundation
import SwiftData

public enum PKChallengeStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case invited
    case accepted
    case completed
    case cancelled
    case expired   // 邀请超时未被认领
    case rejected  // 对手拒绝

    public var displayName: String {
        switch self {
        case .draft:    return "草稿"
        case .invited:  return "待认领"
        case .accepted: return "进行中"
        case .completed: return "已完成"
        case .cancelled: return "已撤回"
        case .expired:  return "已过期"
        case .rejected: return "已拒绝"
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .expired, .rejected: return true
        default: return false
        }
    }
}

public enum PKChallengeType: String, Codable, CaseIterable, Sendable {
    case firstToSettle
    case burnTarget
    case streakSprint

    public var displayName: String {
        switch self {
        case .firstToSettle: return "先结清挑战"
        case .burnTarget: return "消耗目标挑战"
        case .streakSprint: return "连续磨平挑战"
        }
    }

    public var iconName: String {
        switch self {
        case .firstToSettle: return "flag.checkered"
        case .burnTarget: return "flame.fill"
        case .streakSprint: return "bolt.heart.fill"
        }
    }
}

@Model
public final class PKChallenge {
    @Attribute(.unique) public var id: String
    public var type: PKChallengeType
    public var status: PKChallengeStatus
    public var title: String
    public var challengerName: String
    public var challengerCode: String
    public var opponentName: String?
    public var targetCalories: Int
    public var durationDays: Int
    public var linkedTaskId: String?
    public var createdAt: Date
    public var expiresAt: Date        // 邀请过期时间，默认 48h
    public var acceptedAt: Date?
    public var completedAt: Date?
    public var note: String?
    public var isChallenger: Bool     // true=我发起, false=我认领
    public var myProgress: Int        // 我这侧已消耗 kcal（本地计算 / phase2 同步）

    public init(
        id: String = UUID().uuidString,
        type: PKChallengeType,
        title: String,
        challengerName: String,
        challengerCode: String,
        opponentName: String? = nil,
        targetCalories: Int,
        durationDays: Int = 1,
        linkedTaskId: String? = nil,
        status: PKChallengeStatus = .invited,
        note: String? = nil,
        isChallenger: Bool = true,
        expiresInHours: Double = 48
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.title = title
        self.challengerName = challengerName
        self.challengerCode = challengerCode
        self.opponentName = opponentName
        self.targetCalories = max(1, targetCalories)
        self.durationDays = max(1, durationDays)
        self.linkedTaskId = linkedTaskId
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(expiresInHours * 3600)
        self.acceptedAt = nil
        self.completedAt = nil
        self.note = note
        self.isChallenger = isChallenger
        self.myProgress = 0
    }

    // MARK: - Computed

    public var shareCode: String {
        "\(challengerCode)-\(String(id.prefix(6)).uppercased())"
    }

    public var inviteText: String {
        let target = type == .streakSprint ? "\(durationDays) 天" : "\(targetCalories) kcal"
        return "\(challengerName) 邀请你参加 LevelIt「\(title)」：目标 \(target)，邀请码 \(shareCode)。"
    }

    /// 邀请是否已自然过期（未被认领且已超时）
    public var isNaturallyExpired: Bool {
        status == .invited && Date() > expiresAt
    }

    /// 距过期剩余小时数（仅 invited 状态有意义）
    public var hoursUntilExpiry: Int {
        max(0, Int(expiresAt.timeIntervalSince(Date()) / 3600))
    }

    /// 进度百分比（0.0 ~ 1.0）
    public var progressRatio: Double {
        guard targetCalories > 0 else { return 0 }
        return min(1.0, Double(myProgress) / Double(targetCalories))
    }
}
