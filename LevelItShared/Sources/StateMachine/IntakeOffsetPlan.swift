import Foundation

/// 摄入抵扣磨平的**纯决策**：给定任务目标与今日可用运动余额，
/// 算出本次抵扣量与生成任务的目标终态。不触碰 SwiftData / HealthKit，便于单测。
public enum IntakeOffsetPlan {

    public struct Result: Equatable {
        /// 本次抵扣（已钳到 [0, target]）
        public let offset: Int
        /// 生成任务应到达的状态：够还→settled，部分→inProgress，无运动→created
        public let finalStatus: TaskStatus
        /// 抵扣后仍需磨平的余量
        public let remaining: Int

        public var settled: Bool { finalStatus == .settled }

        public init(offset: Int, finalStatus: TaskStatus, remaining: Int) {
            self.offset = offset
            self.finalStatus = finalStatus
            self.remaining = remaining
        }
    }

    /// - Parameters:
    ///   - target: 任务目标（= 摄入热量）
    ///   - available: 今日可用运动余额（E − D，调用方已算好，可能为负）
    public static func plan(target: Int, available: Int) -> Result {
        let safeTarget = max(0, target)
        let offset = max(0, min(safeTarget, available))
        let status: TaskStatus
        if safeTarget > 0 && offset >= safeTarget {
            status = .settled
        } else if offset > 0 {
            status = .inProgress
        } else {
            status = .created
        }
        return Result(offset: offset, finalStatus: status, remaining: max(0, safeTarget - offset))
    }
}
