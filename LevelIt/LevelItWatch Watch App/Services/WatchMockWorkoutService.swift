import Foundation
import Observation
import LevelItShared

/// Watch 端 Mock 运动模拟器 — Phase 3 替换为 HKWorkoutSession
@Observable
final class WatchMockWorkoutService {
    var isRunning = false
    var isPaused = false
    var burnedCalories: Int = 0
    var durationSeconds: Int = 0

    private var timer: Timer?
    private var accumulatedCalories: Double = 0

    func start(mode: TaskMode) {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        // 从已有数据继续 (不清零)
        accumulatedCalories = Double(burnedCalories)
        let caloriesPerSecond = mode.caloriesPerMinute / 60.0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.durationSeconds += 1
            let jitter = Double.random(in: 0.8...1.2)
            self.accumulatedCalories += caloriesPerSecond * jitter
            self.burnedCalories = Int(self.accumulatedCalories)
        }
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
    }

    func reset() {
        stop()
        burnedCalories = 0
        durationSeconds = 0
        accumulatedCalories = 0
    }
}
