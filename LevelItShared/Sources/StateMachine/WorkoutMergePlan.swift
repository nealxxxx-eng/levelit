import Foundation

/// 磨平运动被系统运动中断后，把 HealthKit 时段总消耗合并回任务的**纯决策**。
/// 不触碰 HealthKit / SwiftData，便于单测。
public enum WorkoutMergePlan {

    public struct Result: Equatable {
        /// 合并后的 burnedCalories
        public let burned: Int
        /// 合并后是否达标（可结清）
        public let settled: Bool

        public init(burned: Int, settled: Bool) {
            self.burned = burned
            self.settled = settled
        }
    }

    /// - Parameters:
    ///   - existing: 任务当前 burnedCalories（磨平 App 已记录的）
    ///   - healthKitTotal: `[磨平开始, 现在]` 的 HealthKit 活动能量总和（已含磨平 + 系统运动两段）
    ///   - target: 任务目标 targetBurnCalories
    public static func merge(existing: Int, healthKitTotal: Int, target: Int) -> Result {
        // 取两者较大值：HealthKit 总和已含全部消耗（不与已记录相加，避免重复）；
        // 同时保证单调不回退（HealthKit 偶发偏小时不抹掉已有进度）。
        let burned = max(0, max(existing, healthKitTotal))
        let settled = target > 0 && burned >= target
        return Result(burned: burned, settled: settled)
    }
}
