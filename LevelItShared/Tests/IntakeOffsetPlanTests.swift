import Testing
import Foundation
@testable import LevelItShared

@Suite("摄入抵扣决策")
struct IntakeOffsetPlanTests {

    @Test("运动够还 → 结清 settled")
    func enough() {
        let r = IntakeOffsetPlan.plan(target: 75, available: 118)
        #expect(r.offset == 75)
        #expect(r.finalStatus == .settled)
        #expect(r.remaining == 0)
        #expect(r.settled)
    }

    @Test("运动正好等于目标 → 结清")
    func exact() {
        let r = IntakeOffsetPlan.plan(target: 100, available: 100)
        #expect(r.offset == 100)
        #expect(r.finalStatus == .settled)
    }

    @Test("运动部分 → inProgress，记录余量")
    func partial() {
        let r = IntakeOffsetPlan.plan(target: 300, available: 118)
        #expect(r.offset == 118)
        #expect(r.finalStatus == .inProgress)
        #expect(r.remaining == 182)
    }

    @Test("今日无可用运动 → created（等同普通待磨平）")
    func none() {
        let r = IntakeOffsetPlan.plan(target: 200, available: 0)
        #expect(r.offset == 0)
        #expect(r.finalStatus == .created)
        #expect(r.remaining == 200)
    }

    @Test("余额为负 → 兜底 0 / created")
    func negative() {
        let r = IntakeOffsetPlan.plan(target: 100, available: -50)
        #expect(r.offset == 0)
        #expect(r.finalStatus == .created)
    }

    @Test("目标为 0（异常）→ 不结算、offset 0")
    func zeroTarget() {
        let r = IntakeOffsetPlan.plan(target: 0, available: 100)
        #expect(r.offset == 0)
        #expect(r.finalStatus == .created)
        #expect(r.remaining == 0)
    }
}
