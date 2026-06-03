import SwiftUI
import SwiftData
import Combine
import HealthKit
import LevelItShared

struct WatchWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: DebtTask
    var onFinish: () -> Void

    private var hkManager: WatchHealthKitManager { WatchHealthKitManager.shared }
    @State private var mockWorkout = WatchMockWorkoutService()
    @State private var usingMock = true
    @State private var workoutStarted = false
    @State private var calorieOffset: Int = 0     // 恢复时的已有卡路里偏移
    @State private var durationOffset: Int = 0    // 恢复时的已有时长偏移

    @State private var quoteText = ""
    @State private var shownQuoteIndices: Set<Int> = []
    @State private var quoteTimer: Timer?
    @State private var lastProgressSync: Date = .distantPast
    @State private var lastReliableSync: Date = .distantPast
    @State private var showRecoveryBanner = false

    private var remaining: Int {
        max(0, task.targetBurnCalories - task.burnedCalories)
    }

    private var progress: Double {
        guard task.targetBurnCalories > 0 else { return 0 }
        return min(1.0, Double(task.burnedCalories) / Double(task.targetBurnCalories))
    }

    var body: some View {
        VStack(spacing: 4) {
            if showRecoveryBanner {
                Text("运动已恢复").font(.system(size: 9)).foregroundStyle(.green)
            } else if usingMock && workoutStarted {
                Text("模拟模式").font(.system(size: 9)).foregroundStyle(.orange)
            } else if !usingMock && workoutStarted && !hkHasReportedCalories {
                Text("数据预热中...")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }

            // 心率 (HealthKit 模式下始终显示)
            if workoutStarted && !usingMock {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                    if hkManager.heartRate > 0 {
                        Text("\(Int(hkManager.heartRate))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                    } else {
                        Text("--")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("bpm")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // 进度环
            ZStack {
                Circle().stroke(.gray.opacity(0.3), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)
                VStack(spacing: 0) {
                    Text("\(task.progressPercent)%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("磨平").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)

            // 数据
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text("\(task.burnedCalories)").font(.caption.weight(.bold))
                    Text("已消耗").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                VStack(spacing: 1) {
                    Text("\(remaining)").font(.caption.weight(.bold))
                    Text("剩余").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                VStack(spacing: 1) {
                    Text(formatDuration()).font(.caption.weight(.bold))
                    Text("用时").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }

            // 文案
            if !quoteText.isEmpty {
                Text(quoteText)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2)
                    .padding(.horizontal, 4)
            }

            // HealthKit 无数据时的切换提示
            if showMockSwitch {
                Button {
                    hkManager.stop()
                    usingMock = true
                    // 把当前进度灌给 Mock，不丢失
                    mockWorkout.burnedCalories = task.burnedCalories
                    mockWorkout.durationSeconds = task.durationSeconds
                    calorieOffset = 0  // Mock 已含全部进度，清掉偏移
                    durationOffset = 0
                    mockWorkout.start(mode: task.taskMode)
                    showMockSwitch = false
                } label: {
                    Text("切换到模拟模式")
                        .font(.system(size: 10))
                }
                .tint(.orange)
            }

            // 按钮
            if workoutStarted {
                HStack(spacing: 12) {
                    Button {
                        togglePause()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    }
                    .tint(isPaused ? .green : .yellow)

                    Button { finishWorkout() } label: {
                        Image(systemName: "stop.fill")
                    }
                    .tint(.red)
                }
            } else if startPending {
                ProgressView("授权中...")
                    .font(.caption)
            } else {
                Button { startWorkout() } label: {
                    let title = task.burnedCalories > 0 ? "继续磨平" : "开始磨平"
                    Label(title, systemImage: "play.fill").font(.caption)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
            }
        }
        .navigationTitle(task.foodName)
        .navigationBarBackButtonHidden(workoutStarted)
        .onAppear {
            // 恢复的 session 自动接管，无需用户按按钮
            if hkManager.hasRecoveredSession && (hkManager.isRunning || hkManager.isPaused) && !workoutStarted {
                print("[Recovery] WorkoutView 自动接管: task=\(task.foodName), hkRunning=\(hkManager.isRunning), hkPaused=\(hkManager.isPaused), hkBurned=\(hkManager.burnedCalories)kcal")
                startWorkout()
                showRecoveryBanner = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showRecoveryBanner = false }
                }
            }
        }
        .onDisappear { cleanup() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard workoutStarted else { return }
            syncFromSource()
        }
    }

    // MARK: - State helpers

    private var isPaused: Bool {
        usingMock ? mockWorkout.isPaused : hkManager.isPaused
    }

    private func formatDuration() -> String {
        let s = task.durationSeconds
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Actions

    @State private var startPending = false

    private func startWorkout() {
        // Recovery 恢复的 session 直接接管 (可能是 running 或 paused)
        if hkManager.hasRecoveredSession && (hkManager.isRunning || hkManager.isPaused) {
            launchWorkout(useMock: false)
            return
        }

        let status = WatchHealthKitManager.isCurrentlyAuthorized()

        if status {
            launchWorkout(useMock: false)
        } else {
            // 未授权 → 先请求授权再决定
            startPending = true
            Task {
                await hkManager.requestAuthorization()
                startPending = false
                let authorized = WatchHealthKitManager.isCurrentlyAuthorized()
                launchWorkout(useMock: !authorized)
            }
        }
    }

    private func launchWorkout(useMock: Bool) {
        // 如果是 Recovery 恢复的 session，直接接管，不新建
        if hkManager.hasRecoveredSession && (hkManager.isRunning || hkManager.isPaused) {
            usingMock = false
            calorieOffset = task.burnedCalories - hkManager.burnedCalories
            durationOffset = task.durationSeconds - hkManager.durationSeconds
            if calorieOffset < 0 { calorieOffset = 0 }
            if durationOffset < 0 { durationOffset = 0 }
            hkManager.hasRecoveredSession = false  // 已接管，清标记
        } else {
            // 正常启动流程
            calorieOffset = task.burnedCalories
            durationOffset = task.durationSeconds
        }

        if useMock {
            usingMock = true
            mockWorkout.burnedCalories = task.burnedCalories
            mockWorkout.durationSeconds = task.durationSeconds
            mockWorkout.start(mode: task.taskMode)
        } else if !hkManager.isRunning {
            // 只在 HK 没在跑时才启动 (Recovery 场景已经在跑)
            usingMock = false
            hkManager.start(mode: task.taskMode)
            if !hkManager.isRunning {
                usingMock = true
                mockWorkout.burnedCalories = task.burnedCalories
                mockWorkout.durationSeconds = task.durationSeconds
                mockWorkout.start(mode: task.taskMode)
            }
        }

        if task.status == .created || task.status == .synced || task.status == .paused {
            TaskStateMachine.transition(task, to: .inProgress)
        }

        workoutStarted = true
        // 同步 "已开始/已恢复" 状态给 iPhone
        try? modelContext.save()
        WatchSyncReceiver.shared.sendStatusUpdate(taskId: task.id, status: .inProgress, task: task)

        refreshQuote()
        quoteTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in refreshQuote() }
        WatchHapticManager.tap()
    }

    private func togglePause() {
        if isPaused {
            usingMock ? mockWorkout.resume() : hkManager.resume()
            TaskStateMachine.transition(task, to: .inProgress)
        } else {
            usingMock ? mockWorkout.pause() : hkManager.pause()
            TaskStateMachine.transition(task, to: .paused)
        }
        // Bug fix: 同步暂停/恢复状态给 iPhone
        try? modelContext.save()
        WatchSyncReceiver.shared.sendStatusUpdate(taskId: task.id, status: task.status, task: task)
        WatchHapticManager.tap()
    }

    private func finishWorkout() {
        // 先同步最新数据再停止 (HealthKit 加偏移)
        let burned = usingMock ? mockWorkout.burnedCalories : (calorieOffset + hkManager.burnedCalories)
        let duration = usingMock ? mockWorkout.durationSeconds : (durationOffset + hkManager.durationSeconds)
        task.updateProgress(burnedCalories: burned, durationSeconds: duration)

        usingMock ? mockWorkout.stop() : hkManager.stop()

        if task.burnedCalories >= task.targetBurnCalories {
            // paused → completed 不合法, 需先恢复到 inProgress
            if task.status == .paused {
                TaskStateMachine.transition(task, to: .inProgress)
            }
            TaskStateMachine.transition(task, to: .completed)
        }
        try? modelContext.save()
        WatchSyncReceiver.shared.sendStatusUpdate(taskId: task.id, status: task.status, task: task)
        onFinish()
    }

    @State private var showMockSwitch = false

    @State private var hkHasReportedCalories = false

    /// 每秒从数据源同步到 task
    private func syncFromSource() {
        let burned: Int
        let duration: Int
        if usingMock {
            burned = mockWorkout.burnedCalories
            duration = mockWorkout.durationSeconds
        } else {
            duration = durationOffset + hkManager.durationSeconds

            let hkCalories = hkManager.burnedCalories
            if hkCalories > 0 {
                // HealthKit 已报数据 → 用真实数据
                hkHasReportedCalories = true
                burned = calorieOffset + hkCalories
            } else if !hkHasReportedCalories {
                // 预热中 → 保守估算 (2 kcal/min, 低于绝大多数运动)
                // 这样真实数据到达时进度只会上涨, 不会倒退
                let conservativeRate = 2.0 / 60.0  // 2 kcal/min
                let elapsed = Double(hkManager.durationSeconds)
                burned = calorieOffset + Int(elapsed * conservativeRate)
            } else {
                burned = calorieOffset + hkCalories
            }
        }

        // HealthKit 模式下 60 秒无真实数据 → 提示切换
        if !usingMock && hkManager.durationSeconds > 60 && !hkHasReportedCalories && !showMockSwitch {
            showMockSwitch = true
        }

        let oldPercent = task.progressPercent
        task.updateProgress(burnedCalories: burned, durationSeconds: duration)
        WatchHapticManager.checkAndPlay(oldPercent: oldPercent, newPercent: task.progressPercent)

        // 每秒实时推送进度给 iPhone (仅 sendMessage, iPhone 可达时 ~100ms 到达)
        WatchSyncReceiver.shared.sendProgressRealtime(
            taskId: task.id, burned: task.burnedCalories,
            percent: task.progressPercent, duration: task.durationSeconds
        )

        // 每 5 秒 applicationContext 备份 (iPhone 不可达时的后台兜底)
        if Date().timeIntervalSince(lastProgressSync) >= AppConstants.watchProgressSyncInterval {
            WatchSyncReceiver.shared.sendProgress(
                taskId: task.id, burned: task.burnedCalories,
                percent: task.progressPercent, duration: task.durationSeconds
            )
            lastProgressSync = Date()
        }

        // 每 30 秒用 transferUserInfo 可靠推送 (即使 iPhone 在后台也能收到)
        if Date().timeIntervalSince(lastReliableSync) >= 30 {
            WatchSyncReceiver.shared.sendStatusUpdate(
                taskId: task.id, status: task.status, task: task
            )
            lastReliableSync = Date()
        }

        // 自动完成
        if task.burnedCalories >= task.targetBurnCalories &&
           (task.status == .inProgress || task.status == .paused) {
            usingMock ? mockWorkout.stop() : hkManager.stop()
            if task.status == .paused {
                TaskStateMachine.transition(task, to: .inProgress)
            }
            TaskStateMachine.transition(task, to: .completed)
            try? modelContext.save()
            WatchSyncReceiver.shared.sendStatusUpdate(taskId: task.id, status: .completed, task: task)
            onFinish()
        }
    }

    private func refreshQuote() {
        let stage = MotivationalQuotes.stage(for: task.progressPercent)
        if let pick = MotivationalQuotes.randomQuote(for: stage, excluding: shownQuoteIndices) {
            shownQuoteIndices.insert(pick.index)
            withAnimation {
                quoteText = MotivationalQuotes.render(
                    template: pick.template, food: task.foodName,
                    progress: task.progressPercent, remaining: remaining
                )
            }
        }
    }

    private func cleanup() {
        // 只清理 UI 资源，不停止 workout
        // workout 由 finishWorkout()/autoComplete 显式停止
        // 这样导航切页、系统中断不会杀掉运动
        quoteTimer?.invalidate()
        quoteTimer = nil
    }
}
