import SwiftUI
import SwiftData
import LevelItShared

struct WatchTaskInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]
    @Query private var stats: [UserStats]
    @StateObject private var intakeStore = WatchTodayIntakeStore.shared

    @State private var navigationPath = NavigationPath()
    @State private var newTaskAlert: NewTaskAlert?
    @State private var showOrphanRecovery = false
    @State private var orphanRecoveryCount = 0

    struct NewTaskAlert: Identifiable {
        let id: String  // taskId
        let name: String
        let emoji: String
        let kcal: Int
    }

    private var pendingTasks: [DebtTask] {
        allTasks.filter { $0.isPendingForDay() }
    }

    private var pendingKcal: Int {
        pendingTasks.reduce(0) { $0 + max(0, $1.estimatedCalories - $1.burnedCalories) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 8) {
                    if intakeStore.todayIntakeKcal > 0 {
                        intakeRow
                    }
                    debtHeader

                    NavigationLink(value: "quickadd") {
                        Label("快速接单", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    if pendingTasks.isEmpty {
                        Text("暂无待磨平任务")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top)
                    } else {
                        // 显式 id 让 SwiftUI 用 String 做 diff，
                        // 避免 SwiftData 对象被 invalidate 后 ForEach 访问 stale 引用闪退。
                        ForEach(pendingTasks, id: \.id) { task in
                            Button {
                                navigationPath.append(task)
                            } label: {
                                taskRow(task)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                }
            }
            .navigationTitle("磨平")
            .navigationDestination(for: String.self) { route in
                if route == "quickadd" {
                    WatchQuickAddView { createdTask in
                        // 清掉 quickadd 页，直接跳到运动页
                        navigationPath.removeLast(navigationPath.count)
                        navigationPath.append(createdTask)
                    }
                }
            }
            .navigationDestination(for: DebtTask.self) { task in
                WatchWorkoutContainerView(task: task) {
                    navigationPath = NavigationPath()
                }
            }
            .onAppear {
                ensureStats()
                checkPendingOrphans()
            }
            .task { await checkSessionRecovery() }
            .onReceive(NotificationCenter.default.publisher(for: .newTaskFromiPhone)) { notification in
                guard let info = notification.userInfo,
                      let taskId = info["taskId"] as? String,
                      let name = info["foodName"] as? String,
                      let emoji = info["foodEmoji"] as? String,
                      let kcal = info["kcal"] as? Int
                else { return }
                WatchHapticManager.tap()
                newTaskAlert = NewTaskAlert(id: taskId, name: name, emoji: emoji, kcal: kcal)
            }
            .sheet(item: $newTaskAlert) { alert in
                newTaskSheet(alert)
            }
            .onReceive(NotificationCenter.default.publisher(for: .orphanTasksDetected)) { notification in
                if let count = notification.userInfo?["count"] as? Int {
                    orphanRecoveryCount = count
                    showOrphanRecovery = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .taskWillBeDeletedOnWatch)) { notification in
                guard let taskId = notification.userInfo?["taskId"] as? String else { return }
                handleIncomingTaskDeletion(taskId: taskId)
            }
            .alert("同步任务", isPresented: $showOrphanRecovery) {
                Button("同步到手机") {
                    WatchSyncReceiver.shared.confirmRecovery()
                }
                Button("删除", role: .destructive) {
                    WatchSyncReceiver.shared.declineRecovery()
                }
            } message: {
                Text("手机上缺少 \(orphanRecoveryCount) 个任务，是否同步到手机？")
            }
        }
    }

    private func newTaskSheet(_ alert: NewTaskAlert) -> some View {
        VStack(spacing: 12) {
            Text(alert.emoji)
                .font(.largeTitle)
            Text(alert.name)
                .font(.headline)
            Text("\(alert.kcal) kcal")
                .font(.title3.weight(.bold))
                .foregroundStyle(.orange)
            Text("来自 iPhone 的任务")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                newTaskAlert = nil
                if let task = pendingTasks.first(where: { $0.id == alert.id }) {
                    navigationPath.append(task)
                }
            } label: {
                Label("开始磨平", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button {
                newTaskAlert = nil
            } label: {
                Text("稍后再说")
                    .font(.caption)
            }
        }
    }

    /// Session Recovery — 检查被系统杀掉的运动
    @State private var recoveryChecked = false

    private func checkSessionRecovery() async {
        guard !recoveryChecked else { return }
        recoveryChecked = true

        print("[Recovery] 开始检查可恢复的 HKWorkoutSession...")
        let recovered = await WatchHealthKitManager.shared.checkForRecoverableSession()
        if recovered {
            let hk = WatchHealthKitManager.shared
            print("[Recovery] 发现活跃 session: isRunning=\(hk.isRunning), isPaused=\(hk.isPaused), burned=\(hk.burnedCalories)kcal, duration=\(hk.durationSeconds)s")
            let candidates = pendingTasks.filter { $0.status == .inProgress || $0.status == .paused }
            print("[Recovery] 匹配候选任务: \(candidates.map { "\($0.foodName)(\($0.status.rawValue))" })")
            if let activeTask = candidates.first {
                print("[Recovery] 导航到任务: \(activeTask.foodName) (id=\(activeTask.id.prefix(8)))")
                WatchHapticManager.tap()
                navigationPath.append(activeTask)
            } else {
                print("[Recovery] 无匹配任务，停止孤儿 session")
                WatchHealthKitManager.shared.stop()
            }
        } else {
            print("[Recovery] 无可恢复的 session")
        }
    }

    /// iPhone 端删除任务时，主动弹掉对应的 navigation / sheet，
    /// 防止 SwiftData @Model invalidate 后视图访问 stale 引用闪退。
    private func handleIncomingTaskDeletion(taskId: String) {
        // 1. 关闭可能正在展示该任务的"新任务来了"sheet
        if newTaskAlert?.id == taskId {
            newTaskAlert = nil
        }
        // 2. 把 navigationPath 上指向该任务的所有页面弹掉。
        //    安全做法：直接清栈到根 — 用户体验上稍激进但避免任何 stale 引用。
        if !navigationPath.isEmpty {
            navigationPath = NavigationPath()
        }
    }

    /// 紧凑的"今日摄入"摘要（来自 iPhone 同步）
    private var intakeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.caption)
                .foregroundStyle(.red)
            Text("今日摄入")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(intakeStore.todayIntakeKcal)")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.red)
            Text("kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if intakeStore.todayIntakeCount > 0 {
                Text("· \(intakeStore.todayIntakeCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var debtHeader: some View {
        VStack(spacing: 2) {
            Text("\(pendingKcal)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(pendingKcal > 400 ? .red : pendingKcal > 200 ? .orange : .green)
            Text("kcal 待磨平")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func taskRow(_ task: DebtTask) -> some View {
        HStack {
            Text(task.foodEmoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.foodName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("\(task.estimatedCalories) kcal · \(task.status.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func ensureStats() {
        if stats.isEmpty {
            modelContext.insert(UserStats())
        }
        WatchSyncReceiver.shared.configure(modelContainer: modelContext.container)
    }

    /// 补救 NotificationCenter 通知丢失: 打开页面时主动检查待恢复的孤儿任务
    private func checkPendingOrphans() {
        let ids = WatchSyncReceiver.shared.pendingOrphanTaskIds
        guard !ids.isEmpty else { return }
        orphanRecoveryCount = ids.count
        showOrphanRecovery = true
    }
}
