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
    public var serverId: String?      // 服务端分配的 UUID，nil = 未同步
    public var serverInviteCode: String? // 服务端生成的邀请码，认领必须用它（nil = 未同步）
    public var opponentProgress: Int  // 对手这侧进度（Phase 2 同步）
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
        expiresInHours: Double = 48,
        serverId: String? = nil,
        serverInviteCode: String? = nil
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
        self.serverId = serverId
        self.serverInviteCode = serverInviteCode
        self.opponentProgress = 0
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(expiresInHours * 3600)
        self.acceptedAt = nil
        self.completedAt = nil
        self.note = note
        self.isChallenger = isChallenger
        self.myProgress = 0
    }

    // MARK: - Computed

    /// 本地回退码（仅在尚未同步到服务端时占位用）。
    /// 注意：认领是服务端按 inviteCode 匹配的，本地码与服务端码不同，不能用于真正认领。
    public var shareCode: String {
        "\(challengerCode)-\(String(id.prefix(6)).uppercased())"
    }

    /// 对外展示与分享用的邀请码：优先用服务端返回的（认领必须用它），
    /// 未同步时回退本地占位码。
    public var effectiveInviteCode: String {
        serverInviteCode ?? shareCode
    }

    /// 是否已可被认领（必须已拿到服务端邀请码）
    public var isShareable: Bool {
        serverInviteCode != nil
    }

    public var inviteText: String {
        let target = type == .streakSprint ? "\(durationDays) 天" : "\(targetCalories) kcal"
        return "\(challengerName) 邀请你参加 LevelIt「\(title)」：目标 \(target)，邀请码 \(effectiveInviteCode)。"
    }

    /// 邀请是否已自然过期（未被认领且已超时）
    public var isNaturallyExpired: Bool {
        status == .invited && Date() > expiresAt
    }

    /// 距过期剩余小时数（仅 invited 状态有意义）
    public var hoursUntilExpiry: Int {
        max(0, Int(expiresAt.timeIntervalSince(Date()) / 3600))
    }

    /// 我方进度百分比（0.0 ~ 1.0）
    public var progressRatio: Double {
        guard targetCalories > 0 else { return 0 }
        return min(1.0, Double(myProgress) / Double(targetCalories))
    }

    /// 对手进度百分比（0.0 ~ 1.0）
    public var opponentProgressRatio: Double {
        guard targetCalories > 0 else { return 0 }
        return min(1.0, Double(opponentProgress) / Double(targetCalories))
    }
}
