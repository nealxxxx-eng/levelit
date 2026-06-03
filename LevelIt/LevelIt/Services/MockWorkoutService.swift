import Foundation
import Observation
import LevelItShared

/// Mock 运动模拟器 — 用定时器模拟 Watch 运动消耗
/// Phase 3 替换为真实 HealthKit 数据
@Observable
final class MockWorkoutService {
    var isRunning = false
    var isPaused = false
    var burnedCalories: Int = 0
    var durationSeconds: Int = 0

    private var timer: Timer?
    private var accumulatedCalories: Double = 0

    /// 开始模拟运动
    func start(mode: TaskMode) {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        accumulatedCalories = Double(burnedCalories)  // 从已有数据继续
        let caloriesPerSecond = mode.caloriesPerMinute / 60.0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.durationSeconds += 1
            // 添加随机波动 (0.8x - 1.2x)
            let jitter = Double.random(in: 0.8...1.2)
            self.accumulatedCalories += caloriesPerSecond * jitter
            self.burnedCalories = Int(self.accumulatedCalories)
        }
    }

    /// 暂停
    func pause() {
        isPaused = true
    }

    /// 恢复
    func resume() {
        isPaused = false
    }

    /// 停止
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
    }

    /// 重置
    func reset() {
        stop()
        burnedCalories = 0
        durationSeconds = 0
        accumulatedCalories = 0
    }
}
