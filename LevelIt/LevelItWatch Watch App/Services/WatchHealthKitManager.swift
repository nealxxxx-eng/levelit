import Foundation
import HealthKit
import Observation
import LevelItShared

@Observable
final class WatchHealthKitManager: NSObject {
    /// 单例 — Recovery 和 Workout 共享同一个实例
    static let shared = WatchHealthKitManager()

    var isRunning = false
    var isPaused = false
    var burnedCalories: Int = 0
    var heartRate: Double = 0
    var durationSeconds: Int = 0
    var isAuthorized = false
    var authError: String?
    var hasRecoveredSession = false  // 标记是否从中断恢复

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var durationTimer: Timer?
    private var startDate: Date?
    private var pausedDuration: TimeInterval = 0   // 累计暂停时长
    private var pauseStartDate: Date?              // 当前暂停开始时间
    private var isSelfStopping = false             // 标记是否是自身调用 stop

    // MARK: - 同步检查授权

    static func isCurrentlyAuthorized() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let store = HKHealthStore()
        let status = store.authorizationStatus(for: HKQuantityType.workoutType())
        return status == .sharingAuthorized
    }

    // MARK: - 请求授权

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authError = "不支持 HealthKit"
            return
        }

        // 写入权限: workout + activeEnergy + heartRate
        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]

        // 读取权限
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKObjectType.workoutType(),
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            isAuthorized = true
        } catch {
            authError = "授权失败: \(error.localizedDescription)"
            isAuthorized = false
        }
    }

    // MARK: - 开始运动

    func start(mode: TaskMode) {
        guard !isRunning else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = activityType(for: mode)
        config.locationType = locationTypeFor(mode)
        if mode == .swimming {
            config.swimmingLocationType = .pool
        }

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            guard let session else {
                authError = "无法创建 session"
                return
            }

            builder = session.associatedWorkoutBuilder()
            guard let builder else {
                authError = "无法创建 builder"
                return
            }

            session.delegate = self
            builder.delegate = self

            // 配置数据源 — 收集运动数据 + 心率
            let dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )
            dataSource.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)
            builder.dataSource = dataSource

            let now = Date()
            startDate = now

            // 启动 session
            session.startActivity(with: now)

            // 开始数据收集 (用 async 版本确保成功)
            Task {
                do {
                    try await builder.beginCollection(at: now)
                } catch {
                    await MainActor.run {
                        self.authError = "数据收集启动失败: \(error.localizedDescription)"
                    }
                }
            }

            isRunning = true
            isPaused = false
            startDurationTimer()

        } catch {
            authError = "启动失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 暂停/恢复/停止

    func pause() {
        session?.pause()
        isPaused = true
        pauseStartDate = Date()
        durationTimer?.invalidate()
    }

    func resume() {
        session?.resume()
        isPaused = false
        if let pauseStart = pauseStartDate {
            pausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartDate = nil
        }
        startDurationTimer()
    }

    func stop() {
        durationTimer?.invalidate()
        durationTimer = nil

        // 如果在暂停中停止，把最后一段暂停时间也累计上
        if let pauseStart = pauseStartDate {
            pausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartDate = nil
        }

        isRunning = false
        isPaused = false
        isSelfStopping = true

        guard let session, let builder else {
            clearSessionRefs()
            return
        }

        let endDate = Date()
        Task {
            // 正确顺序: 先结束数据收集, 再结束 session, 最后 finalize
            do {
                try await builder.endCollection(at: endDate)
            } catch {
                print("[HKManager] endCollection failed: \(error.localizedDescription)")
            }
            session.end()
            do {
                try await builder.finishWorkout()
            } catch {
                print("[HKManager] finishWorkout failed: \(error.localizedDescription)")
            }
            await MainActor.run {
                self.clearSessionRefs()
            }
        }
    }

    /// 清理 session/builder 引用, 释放 HealthKit 资源
    private func clearSessionRefs() {
        session?.delegate = nil
        builder?.delegate = nil
        session = nil
        builder = nil
        isSelfStopping = false
    }

    func reset() {
        stop()
        burnedCalories = 0
        heartRate = 0
        durationSeconds = 0
        startDate = nil
        pausedDuration = 0
        pauseStartDate = nil
        hasRecoveredSession = false
    }

    // MARK: - Session Recovery

    /// 检查是否有被系统中断的活跃 workout session
    func checkForRecoverableSession() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[Recovery] HealthKit 不可用")
            return false
        }

        do {
            let recovered = try await healthStore.recoverActiveWorkoutSession()
            if let recovered {
                session = recovered
                builder = recovered.associatedWorkoutBuilder()
                session?.delegate = self
                builder?.delegate = self

                // 恢复状态
                isRunning = recovered.state == .running
                isPaused = recovered.state == .paused
                startDate = recovered.startDate
                hasRecoveredSession = true
                isAuthorized = true  // 能恢复说明之前已授权

                // 用 builder.elapsedTime (真实运动时长) 反推暂停累计
                if let start = startDate, let builder {
                    let wallClock = Date().timeIntervalSince(start)
                    pausedDuration = max(0, wallClock - builder.elapsedTime)
                }
                if isPaused {
                    pauseStartDate = Date()
                }

                // 从 builder 读取已有数据
                updateMetrics()
                durationSeconds = max(0, Int(builder?.elapsedTime ?? 0))
                if isRunning { startDurationTimer() }

                print("[Recovery] HK session 恢复成功: state=\(recovered.state.rawValue), startDate=\(startDate?.description ?? "nil"), elapsed=\(durationSeconds)s, burned=\(burnedCalories)kcal, hr=\(heartRate)bpm")
                return true
            } else {
                print("[Recovery] recoverActiveWorkoutSession 返回 nil")
            }
        } catch {
            print("[Recovery] recoverActiveWorkoutSession 失败: \(error.localizedDescription)")
        }
        return false
    }

    // MARK: - Private

    private func activityType(for mode: TaskMode) -> HKWorkoutActivityType {
        switch mode {
        case .walk:               return .walking
        case .indoorWalk:         return .walking
        case .mix:                return .mixedCardio
        case .run:                return .running
        case .indoorRun:          return .running
        case .cycling:            return .cycling
        case .indoorCycling:      return .cycling
        case .elliptical:         return .elliptical
        case .rowing:             return .rowing
        case .coreTraining:       return .coreTraining
        case .functionalTraining: return .functionalStrengthTraining
        case .swimming:           return .swimming
        }
    }

    func locationTypeFor(_ mode: TaskMode) -> HKWorkoutSessionLocationType {
        mode.isIndoor ? .indoor : .outdoor
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused, let start = self.startDate else { return }
            let total = Date().timeIntervalSince(start) - self.pausedDuration
            self.durationSeconds = max(0, Int(total))
        }
    }

    private func updateMetrics() {
        guard let builder else { return }

        // Active Energy Burned
        let energyType = HKQuantityType(.activeEnergyBurned)
        if let stats = builder.statistics(for: energyType),
           let sum = stats.sumQuantity() {
            let kcal = sum.doubleValue(for: .kilocalorie())
            burnedCalories = Int(kcal)
        }

        // Heart Rate
        let hrType = HKQuantityType(.heartRate)
        if let stats = builder.statistics(for: hrType),
           let hr = stats.mostRecentQuantity() {
            heartRate = hr.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchHealthKitManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch toState {
            case .running:
                self.isRunning = true
                self.isPaused = false
            case .paused:
                self.isPaused = true
            case .ended:
                self.isRunning = false
                self.isPaused = false
                self.durationTimer?.invalidate()
                self.durationTimer = nil
                // 外部终止 (系统或其他 app 抢占): 清理引用释放 session
                if !self.isSelfStopping {
                    print("[HKManager] session 被外部终止 (from=\(fromState.rawValue))")
                    self.clearSessionRefs()
                }
            default: break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.authError = "session 出错: \(error.localizedDescription)"
            self.isRunning = false
            self.isPaused = false
            self.durationTimer?.invalidate()
            self.durationTimer = nil
            self.clearSessionRefs()
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchHealthKitManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        DispatchQueue.main.async { [weak self] in
            self?.updateMetrics()
        }
    }
}
