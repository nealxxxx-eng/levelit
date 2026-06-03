import SwiftUI
import SwiftData
import WatchConnectivity
import LevelItShared

/// 智能分流视图 — 根据任务状态和 Watch 配对情况显示不同界面
struct TaskDetailView: View {
    @Bindable var task: DebtTask
    var onCompleted: (DebtTask) -> Void

    private var hasWatch: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired
    }

    var body: some View {
        Group {
            if task.status == .completed || task.status == .settled {
                // 已完成 → 结果页
                ResultView(task: task)
            } else if task.status == .inProgress || task.status == .paused {
                if hasWatch {
                    // Watch 运动中 → 只读监控
                    WatchMonitorView(task: task, onCompleted: onCompleted)
                } else {
                    // 无 Watch，降级模拟模式
                    TaskProgressView(task: task, onCompleted: onCompleted)
                }
            } else {
                // created / synced → 等待开始
                if hasWatch {
                    WatchWaitingView(task: task)
                } else {
                    TaskProgressView(task: task, onCompleted: onCompleted)
                }
            }
        }
    }
}

/// "等待 Watch 开始" 视图
struct WatchWaitingView: View {
    @Bindable var task: DebtTask

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            Text(task.foodEmoji)
                .font(.system(size: 64))

            Text(task.foodName)
                .font(.title2.weight(.bold))

            Text("\(task.estimatedCalories) kcal · \(task.taskMode.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 40)

            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "applewatch")
                    .font(.system(size: 40))
                    .foregroundStyle(DS.Colors.accent)

                Text("抬手开始磨平")
                    .font(.headline)

                Text("在 Apple Watch 上打开磨平 App\n点击此任务开始运动")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .navigationTitle(task.foodName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Watch 运动监控视图 — 只读显示来自 Watch 的实时进度
struct WatchMonitorView: View {
    @Bindable var task: DebtTask
    var onCompleted: (DebtTask) -> Void

    @State private var isDisconnected = false
    @State private var lastUpdateTime = Date()

    private var progress: Double {
        guard task.targetBurnCalories > 0 else { return 0 }
        return min(1.0, Double(task.burnedCalories) / Double(task.targetBurnCalories))
    }

    private var remaining: Int {
        max(0, task.targetBurnCalories - task.burnedCalories)
    }

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            // Watch 标识
            HStack {
                Image(systemName: "applewatch")
                    .foregroundStyle(DS.Colors.accent)
                Text(task.status == .paused ? "Watch 已暂停" : "Watch 运动中")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Colors.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DS.Colors.accent.opacity(0.1))
            .clipShape(Capsule())

            // 进度环
            ZStack {
                Circle()
                    .stroke(DS.Colors.cardBackground, lineWidth: 16)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        DS.Colors.accent,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                VStack(spacing: 4) {
                    Text("\(task.progressPercent)%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("已磨平")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)

            // 数据面板
            HStack(spacing: 0) {
                statColumn(value: "\(task.burnedCalories)", unit: "kcal", label: "已消耗")
                Divider().frame(height: 40)
                statColumn(value: "\(remaining)", unit: "kcal", label: "剩余")
                Divider().frame(height: 40)
                statColumn(value: formatDuration(task.durationSeconds), unit: "", label: "用时")
            }
            .padding()
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))

            // 暂停提示 — 引导去 Watch 恢复
            if task.status == .paused {
                VStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "applewatch")
                        .font(.title2)
                        .foregroundStyle(DS.Colors.accent)
                    Text("运动已暂停")
                        .font(.subheadline.weight(.medium))
                    Text("在 Apple Watch 上点击此任务继续运动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(DS.Colors.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }

            // 断连提示
            if isDisconnected && task.status == .inProgress {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.orange)
                    Text("Watch 已断开连接，进度将在重新连接后更新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }

            Spacer()
        }
        .padding()
        .navigationTitle(task.foodName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 用任务的最后同步时间初始化，避免刚进入就误报断连
            lastUpdateTime = task.lastSyncAt ?? Date()
        }
        .onChange(of: task.burnedCalories) { _, _ in
            lastUpdateTime = Date()
            isDisconnected = false
        }
        .onChange(of: task.durationSeconds) { _, _ in
            lastUpdateTime = Date()
            isDisconnected = false
        }
        .onChange(of: task.status) { _, newStatus in
            if newStatus == .completed || newStatus == .settled {
                onCompleted(task)
            }
        }
        .task {
            // 每 30 秒检查一次，超过 60 秒无更新才视为断连
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if task.status == .inProgress &&
                   Date().timeIntervalSince(lastUpdateTime) > 60 {
                    isDisconnected = true
                }
            }
        }
    }

    private func statColumn(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.headline).contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
