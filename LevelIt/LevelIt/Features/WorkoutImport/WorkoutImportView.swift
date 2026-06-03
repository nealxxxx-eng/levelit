import SwiftUI
import SwiftData
import LevelItShared

/// 已导入的运动 UUID 账本 (SwiftData 持久化)
enum ImportedWorkoutLedger {
    static func importedIds(in context: ModelContext) -> Set<String> {
        let records = (try? context.fetch(FetchDescriptor<ImportedWorkoutRecord>())) ?? []
        return Set(records.map(\.id))
    }

    static func markImported(_ workouts: [HealthKitImportService.ImportableWorkout], in context: ModelContext) {
        let existing = importedIds(in: context)
        for workout in workouts where !existing.contains(workout.id.uuidString) {
            context.insert(ImportedWorkoutRecord(
                id: workout.id.uuidString,
                calories: workout.calories,
                durationSeconds: Int(workout.duration)
            ))
        }
    }

    static func isImported(_ id: String, in context: ModelContext) -> Bool {
        importedIds(in: context).contains(id)
    }
}

/// 运动卡路里余额 (SwiftData 持久化, 按日期隔离)
enum CalorieBalance {
    static func availableCalories(in context: ModelContext) -> Int {
        currentBalance(in: context)?.calories ?? 0
    }

    static func availableDuration(in context: ModelContext) -> Int {
        currentBalance(in: context)?.durationSeconds ?? 0
    }

    static func deposit(calories: Int, duration: Int, in context: ModelContext) {
        guard calories > 0 || duration > 0 else { return }
        let balance = ensureTodayBalance(in: context)
        balance.calories += max(0, calories)
        balance.durationSeconds += max(0, duration)
        balance.updatedAt = Date()
    }

    /// 取出所需卡路里, 返回实际取出 (calories, duration), 时长按比例
    static func withdraw(needed: Int, in context: ModelContext) -> (calories: Int, duration: Int) {
        guard needed > 0, let balance = currentBalance(in: context) else { return (0, 0) }
        let currentCal = balance.calories
        let currentDur = balance.durationSeconds
        guard currentCal > 0 else { return (0, 0) }

        let consumed = min(needed, currentCal)
        let durRatio = currentCal > 0 ? Double(consumed) / Double(currentCal) : 0
        let consumedDur = Int(Double(currentDur) * durRatio)

        balance.calories = currentCal - consumed
        balance.durationSeconds = currentDur - consumedDur
        balance.updatedAt = Date()
        return (consumed, consumedDur)
    }

    private static func currentBalance(in context: ModelContext) -> DailyCalorieBalance? {
        let today = DailyCalorieBalance.todayKey()
        let balances = (try? context.fetch(FetchDescriptor<DailyCalorieBalance>())) ?? []
        return balances.first { $0.dateKey == today }
    }

    private static func ensureTodayBalance(in context: ModelContext) -> DailyCalorieBalance {
        if let balance = currentBalance(in: context) {
            return balance
        }
        let balance = DailyCalorieBalance()
        context.insert(balance)
        return balance
    }
}

/// 显示今日外部运动记录，让用户选择分配给哪个待磨平任务
struct WorkoutImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]
    @Query private var stats: [UserStats]

    @State private var workouts: [HealthKitImportService.ImportableWorkout] = []
    @State private var isLoading = true
    @State private var appliedTask: DebtTask?

    private var store: HealthKitDataStore { .shared }
    @State private var appliedCalories: Int = 0

    private var pendingTasks: [DebtTask] {
        allTasks.filter { $0.isPendingForDay() }
    }

    private var workoutCalories: Int {
        workouts.reduce(0) { $0 + $1.calories }
    }

    private var naturalCalories: Int {
        NaturalAllowance.available
    }

    private var totalAvailableCalories: Int {
        workoutCalories + CalorieBalance.availableCalories(in: modelContext) + naturalCalories
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载运动数据...")
            } else if workouts.isEmpty && CalorieBalance.availableCalories(in: modelContext) <= 0 && naturalCalories <= 0 {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: DS.Spacing.lg) {
                        header
                        workoutList
                        if !pendingTasks.isEmpty {
                            taskSection
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("导入运动")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadWorkouts() }
        .sheet(item: $appliedTask) { task in
            appliedResultSheet(task)
        }
    }

    private func loadWorkouts() async {
        guard await store.ensureAuthorization() else {
            isLoading = false
            return
        }

        await store.refreshTodayWorkouts(force: true)
        workouts = store.todayExternalWorkouts.filter { !ImportedWorkoutLedger.isImported($0.id.uuidString, in: modelContext) }
        isLoading = false
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: "figure.run.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("没有可导入的运动记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("今日运动数据已全部导入，或还没有外部运动")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - 今日运动总览

    private var header: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("可抵扣的运动")
                .font(.title3.weight(.bold))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(totalAvailableCalories)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.accent)
                Text("kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let parts = [
                workoutCalories > 0 ? "运动 \(workoutCalories)" : nil,
                CalorieBalance.availableCalories(in: modelContext) > 0 ? "余额 \(CalorieBalance.availableCalories(in: modelContext))" : nil,
                naturalCalories > 0 ? "自然消耗 \(naturalCalories)" : nil
            ].compactMap { $0 }

            if !parts.isEmpty {
                Text(parts.joined(separator: " + ") + " kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("来自 \(workoutSourceSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var workoutSourceSummary: String {
        let sources = Set(workouts.map(\.source))
        return sources.joined(separator: "、")
    }

    // MARK: - 运动列表

    private var workoutList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("运动记录")
                .font(.headline)

            ForEach(workouts) { workout in
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: workout.iconName)
                        .font(.title3)
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.displayName)
                            .font(.body.weight(.medium))
                        HStack(spacing: 8) {
                            Text(workout.source)
                            Text("\(workout.durationMinutes)分钟")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(workout.calories) kcal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DS.Colors.accent)
                }
                .padding(DS.Spacing.md)
                .background(DS.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
        }
    }

    // MARK: - 选择要抵扣的任务

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("抵扣到哪个任务？")
                .font(.headline)

            ForEach(pendingTasks, id: \.id) { task in
                let remaining = max(0, task.estimatedCalories - task.burnedCalories)
                Button {
                    applyCalories(to: task)
                } label: {
                    HStack(spacing: DS.Spacing.md) {
                        Text(task.foodEmoji)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.foodName)
                                .font(.body.weight(.medium))
                            Text("剩余 \(remaining) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(DS.Colors.accent)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 抵扣逻辑 (走领域层)

    private func applyCalories(to task: DebtTask) {
        let needed = max(0, task.targetBurnCalories - task.burnedCalories)

        // 1. 优先消耗自然余额 (免费额度)
        let naturalConsumed = NaturalAllowance.consume(needed)
        var totalConsumed = naturalConsumed
        var totalDur = 0

        // 2. 剩余不足部分从运动中补
        let remainingAfterNatural = needed - naturalConsumed

        if remainingAfterNatural > 0 {
            // 3. 所有未导入 workout 全部存入余额，标记为已导入
            if !workouts.isEmpty {
                let wCal = workoutCalories
                let wDur = workouts.reduce(0) { $0 + Int($1.duration) }
                CalorieBalance.deposit(calories: wCal, duration: wDur, in: modelContext)
                ImportedWorkoutLedger.markImported(workouts, in: modelContext)
                workouts = []
            }

            // 4. 从运动余额中取出所需
            let (consumedCal, consumedDur) = CalorieBalance.withdraw(needed: remainingAfterNatural, in: modelContext)
            totalConsumed += consumedCal
            totalDur = consumedDur
        }

        guard totalConsumed > 0 else { return }
        let consumedCal = totalConsumed
        let consumedDur = totalDur

        // 3. 更新任务进度
        task.updateProgress(
            burnedCalories: task.burnedCalories + consumedCal,
            durationSeconds: task.durationSeconds + consumedDur
        )

        // 4. 状态机流转 (完整链路: → inProgress → completed → settled)
        if task.status == .created || task.status == .synced || task.status == .paused {
            TaskStateMachine.transition(task, to: .inProgress)
        }

        if task.burnedCalories >= task.targetBurnCalories {
            TaskStateMachine.transition(task, to: .completed)
            TaskStateMachine.transition(task, to: .settled)

            if let userStats = stats.first {
                userStats.recordCompletion(burnedCalories: task.burnedCalories)
            }
        }

        // 5. 持久化 (失败则回滚所有余额)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            if naturalConsumed > 0 { NaturalAllowance.rollback(naturalConsumed) }
            return
        }

        // 6. 同步到 Watch
        WCSyncService.shared.sendTaskSnapshot(task)

        appliedCalories = consumedCal
        appliedTask = task
    }

    // MARK: - 抵扣结果

    private func appliedResultSheet(_ task: DebtTask) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            let isSettled = task.burnedCalories >= task.estimatedCalories

            Image(systemName: isSettled ? "checkmark.seal.fill" : "flame.fill")
                .font(.system(size: 48))
                .foregroundStyle(isSettled ? .green : DS.Colors.accent)

            Text(isSettled ? "已结清!" : "已抵扣!")
                .font(.title2.weight(.bold))

            VStack(spacing: DS.Spacing.sm) {
                HStack {
                    Text("\(task.foodEmoji) \(task.foodName)")
                    Spacer()
                    Text("\(task.estimatedCalories) kcal")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("本次抵扣")
                    Spacer()
                    Text("+\(appliedCalories) kcal")
                        .foregroundStyle(.green)
                }
                HStack {
                    Text("累计消耗")
                    Spacer()
                    Text("\(task.burnedCalories) kcal")
                        .foregroundStyle(DS.Colors.accent)
                }
                if !isSettled {
                    let remaining = task.estimatedCalories - task.burnedCalories
                    HStack {
                        Text("还剩")
                        Spacer()
                        Text("\(remaining) kcal")
                            .foregroundStyle(.orange)
                    }
                }
                if CalorieBalance.availableCalories(in: modelContext) > 0 {
                    HStack {
                        Text("运动余额")
                        Spacer()
                        Text("\(CalorieBalance.availableCalories(in: modelContext)) kcal")
                            .foregroundStyle(.blue)
                    }
                }
                if NaturalAllowance.available > 0 {
                    HStack {
                        Text("自然消耗余额")
                        Spacer()
                        Text("\(NaturalAllowance.available) kcal")
                            .foregroundStyle(.green)
                    }
                }
            }
            .font(.subheadline)
            .padding()
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            if CalorieBalance.availableCalories(in: modelContext) > 0 && !pendingTasks.isEmpty {
                Button {
                    appliedTask = nil
                } label: {
                    Text("继续抵扣其他任务")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
            }

            Button {
                appliedTask = nil
                dismiss()
            } label: {
                Text("完成")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(CalorieBalance.availableCalories(in: modelContext) > 0 && !pendingTasks.isEmpty ? DS.Colors.cardBackground : DS.Colors.accent)
                    .foregroundStyle(CalorieBalance.availableCalories(in: modelContext) > 0 && !pendingTasks.isEmpty ? Color.primary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
        }
        .padding()
    }
}
