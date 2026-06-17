import Testing
import Foundation
@testable import LevelItShared

@Suite("PK 运动统计窗口")
struct PKProgressWindowTests {

    private func at(_ unix: TimeInterval) -> Date { Date(timeIntervalSince1970: unix) }

    @Test("上界取 now，今天的运动落在窗口内（回归：旧实现会漏掉）")
    func windowCoversToday() {
        let start = at(1_000_000)              // 挑战开始
        let now   = at(1_000_000 + 5 * 86400)  // 5 天后的现在
        let w = PKProgressWindow.range(start: start, now: now)

        #expect(w.start == start)
        #expect(w.end == now)

        // 今天（now 前一刻）的运动应落在 [start, end) 内
        let todayWorkout = now.addingTimeInterval(-60)
        #expect(todayWorkout >= w.start && todayWorkout < w.end)

        // 对照旧逻辑：start + 2 天 的上界会把上面这条今天的运动排除
        let oldEnd = start.addingTimeInterval(2 * 86400)
        #expect(!(todayWorkout < oldEnd))  // 证明旧上界确实漏掉今天
    }

    @Test("开始前的运动不计入（下界 = start）")
    func excludesBeforeStart() {
        let start = at(1_000_000)
        let now   = at(1_000_000 + 86400)
        let w = PKProgressWindow.range(start: start, now: now)
        let beforeStart = start.addingTimeInterval(-60)
        #expect(beforeStart < w.start)
    }

    @Test("now 早于 start（异常）时退化为空窗口，不产生负区间")
    func degenerateWhenNowBeforeStart() {
        let start = at(2_000_000)
        let now   = at(1_000_000)
        let w = PKProgressWindow.range(start: start, now: now)
        #expect(w.end == start)          // max(start, now) = start
        #expect(w.end >= w.start)        // 不会出现 end < start
    }
}
