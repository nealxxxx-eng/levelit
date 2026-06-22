import Testing
import Foundation
@testable import LevelItShared

@Suite("运动中断合并决策")
struct WorkoutMergePlanTests {

    @Test("系统+磨平总量达标 → 结清")
    func reachesTarget() {
        let r = WorkoutMergePlan.merge(existing: 50, healthKitTotal: 120, target: 100)
        #expect(r.burned == 120)
        #expect(r.settled)
    }

    @Test("总量未达标 → 更新进度但不结清")
    func belowTarget() {
        let r = WorkoutMergePlan.merge(existing: 50, healthKitTotal: 80, target: 100)
        #expect(r.burned == 80)
        #expect(!r.settled)
    }

    @Test("HealthKit 偶发偏小 → 取已有，单调不回退")
    func noRegression() {
        let r = WorkoutMergePlan.merge(existing: 90, healthKitTotal: 70, target: 100)
        #expect(r.burned == 90)
        #expect(!r.settled)
    }

    @Test("正好达标")
    func exact() {
        let r = WorkoutMergePlan.merge(existing: 0, healthKitTotal: 100, target: 100)
        #expect(r.burned == 100)
        #expect(r.settled)
    }

    @Test("都为 0 → 0、不结清")
    func zero() {
        let r = WorkoutMergePlan.merge(existing: 0, healthKitTotal: 0, target: 100)
        #expect(r.burned == 0)
        #expect(!r.settled)
    }

    @Test("target 为 0（异常）→ 不结清")
    func zeroTarget() {
        let r = WorkoutMergePlan.merge(existing: 10, healthKitTotal: 50, target: 0)
        #expect(!r.settled)
    }
}
