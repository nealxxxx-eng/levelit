import Testing
import Foundation
@testable import LevelItShared

@Suite("Haptic Schedule Tests")
struct HapticScheduleTests {

    /// Haptic 节点: 25%, 50%, 75%, 100%
    /// 当进度首次跨过某节点时触发一次

    @Test("从 0% 更新到 30%: 触发 25% 节点")
    func triggers25() {
        let triggered = hapticNodes(oldPercent: 0, newPercent: 30)
        #expect(triggered == [25])
    }

    @Test("从 20% 更新到 55%: 触发 25% 和 50%")
    func triggers25And50() {
        let triggered = hapticNodes(oldPercent: 20, newPercent: 55)
        #expect(triggered == [25, 50])
    }

    @Test("从 70% 更新到 100%: 触发 75% 和 100%")
    func triggers75And100() {
        let triggered = hapticNodes(oldPercent: 70, newPercent: 100)
        #expect(triggered == [75, 100])
    }

    @Test("从 0% 直接到 100%: 触发全部 4 个节点")
    func triggersAll() {
        let triggered = hapticNodes(oldPercent: 0, newPercent: 100)
        #expect(triggered == [25, 50, 75, 100])
    }

    @Test("从 26% 到 30%: 不触发 (25% 已过)")
    func noTrigger() {
        let triggered = hapticNodes(oldPercent: 26, newPercent: 30)
        #expect(triggered.isEmpty)
    }

    @Test("从 100% 到 150%: 不重复触发")
    func noRepeatAfter100() {
        let triggered = hapticNodes(oldPercent: 100, newPercent: 150)
        #expect(triggered.isEmpty)
    }

    @Test("进度不变: 不触发")
    func noChangeNoTrigger() {
        let triggered = hapticNodes(oldPercent: 50, newPercent: 50)
        #expect(triggered.isEmpty)
    }

    // MARK: - Haptic 节点计算逻辑 (与 WatchHapticManager 保持一致)

    private static let hapticThresholds = [25, 50, 75, 100]

    private func hapticNodes(oldPercent: Int, newPercent: Int) -> [Int] {
        Self.hapticThresholds.filter { threshold in
            oldPercent < threshold && newPercent >= threshold
        }
    }
}
