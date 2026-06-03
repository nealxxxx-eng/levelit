import SwiftUI
import SwiftData
import LevelItShared

/// 事后编辑某条 MealIntake：改食物名 / 餐次 / 实际摄入热量。
///
/// 关联 DebtTask 处理：
/// - 任务状态为 created/synced（未开始）时，弹 Alert 询问是否同步任务热量
/// - 任务已 inProgress / paused / settled / cancelled / expired 时，仅改 intake，提示"任务已锁定"
struct MealIntakeEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let intake: MealIntake
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]

    // Draft state（避免每次输入都立即写库）
    @State private var foodName: String = ""
    @State private var mealKind: MealKind = .snack
    @State private var kcal: Int = 0
    @State private var didLoad = false

    // 保存时的关联任务确认
    @State private var pendingSync: PendingSync?

    // 删除确认
    @State private var showDeleteConfirm = false

    private var linkedActiveTask: DebtTask? {
        guard let id = intake.debtTaskId,
              let t = allTasks.first(where: { $0.id == id })
        else { return nil }
        // 仅 created/synced 可以同步改 kcal；其他状态视为锁定
        return (t.status == .created || t.status == .synced) ? t : nil
    }

    private var linkedLockedTask: DebtTask? {
        guard let id = intake.debtTaskId,
              let t = allTasks.first(where: { $0.id == id })
        else { return nil }
        return (t.status == .created || t.status == .synced) ? nil : t
    }

    private var hasChanges: Bool {
        foodName != intake.foodName
            || mealKind != intake.mealKind
            || kcal != intake.estimatedCalories
    }

    var body: some View {
        Form {
            foodSection
            mealKindSection
            calorieSection
            if let locked = linkedLockedTask {
                lockedTaskNoticeSection(locked)
            }
            metaSection
            deleteSection
        }
        .navigationTitle("编辑摄入")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { onSavePressed() }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || foodName.isEmpty || kcal < AppConstants.minCalories)
            }
        }
        .onAppear { loadDraft() }
        .alert("同步磨平任务？", isPresented: .init(
            get: { pendingSync != nil },
            set: { if !$0 { pendingSync = nil } }
        )) {
            if let p = pendingSync {
                Button("同步改任务") {
                    saveAll(syncTask: true, taskToSync: p.task)
                }
                Button("仅改摄入") {
                    saveAll(syncTask: false, taskToSync: nil)
                }
                Button("取消", role: .cancel) {}
            }
        } message: {
            if let p = pendingSync {
                Text("摄入由 \(intake.estimatedCalories) → \(kcal) kcal。\n关联的磨平任务（\(p.task.foodName) · \(p.task.estimatedCalories) kcal）是否同步调整？")
            }
        }
        .alert("删除这条摄入记录？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { deleteIntake() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: - Sections

    private var foodSection: some View {
        Section("食物") {
            HStack {
                Text(intake.foodEmoji)
                    .font(.title2)
                TextField("食物名", text: $foodName)
            }
        }
    }

    private var mealKindSection: some View {
        Section("餐次") {
            Picker("餐次", selection: $mealKind) {
                ForEach(MealKind.allCases) { kind in
                    Text("\(kind.emoji) \(kind.displayName)").tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var calorieSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Text("\(kcal)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.accent)
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper("", value: $kcal, in: AppConstants.minCalories...5000, step: 10)
                        .labelsHidden()
                }
                Slider(
                    value: Binding(
                        get: { Double(kcal) },
                        set: { kcal = Int($0) }
                    ),
                    in: Double(AppConstants.minCalories)...Double(max(intake.originalCalories, kcal, 1500)),
                    step: 10
                )
                .tint(DS.Colors.accent)

                if intake.originalCalories != kcal {
                    let diff = kcal - intake.originalCalories
                    Text(diff > 0
                         ? "比原始识别多 \(diff) kcal"
                         : "比原始识别少 \(-diff) kcal")
                        .font(.caption)
                        .foregroundStyle(diff > 0 ? .red : .green)
                }
            }
        } header: {
            Text("实际摄入热量")
        } footer: {
            Text("AI 原始识别 \(intake.originalCalories) kcal · 当前记录 \(intake.estimatedCalories) kcal")
        }
    }

    private func lockedTaskNoticeSection(_ task: DebtTask) -> some View {
        Section {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("关联任务已锁定")
                        .font(.subheadline.weight(.medium))
                    Text("\(task.foodName) · \(task.status.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("修改摄入热量不会影响该磨平任务（已开始/已完成的任务保留账本完整性）")
        }
    }

    private var metaSection: some View {
        Section("记录信息") {
            row(label: "记录时间", value: timeString(intake.takenAt))
            row(label: "判定", value: "\(intake.verdictKind.displayName)")
            if intake.diners > 1 {
                row(label: "分餐", value: "1/\(intake.diners) 份")
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("删除此摄入记录")
                }
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - 保存逻辑

    private func loadDraft() {
        guard !didLoad else { return }
        foodName = intake.foodName
        mealKind = intake.mealKind
        kcal = intake.estimatedCalories
        didLoad = true
    }

    private func onSavePressed() {
        // 若有可同步的关联任务且 kcal 改变了，弹 Alert 让用户决定
        if let active = linkedActiveTask, kcal != intake.estimatedCalories {
            pendingSync = PendingSync(task: active)
        } else {
            saveAll(syncTask: false, taskToSync: nil)
        }
    }

    private func saveAll(syncTask: Bool, taskToSync: DebtTask?) {
        intake.foodName = foodName
        intake.mealKind = mealKind
        intake.estimatedCalories = kcal

        let taskToNotify: DebtTask?
        if syncTask, let task = taskToSync {
            task.estimatedCalories = kcal
            task.targetBurnCalories = kcal
            // 重新计算 estimatedMinutes
            task.estimatedMinutes = CalorieCalculator.calculateMinutes(
                calories: kcal, mode: task.taskMode
            )
            taskToNotify = task
        } else {
            taskToNotify = nil
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return
        }
        if let taskToNotify {
            WCSyncService.shared.sendTaskSnapshot(taskToNotify)
        }
        WCSyncService.shared.pushTodayIntakeContext(modelContext: modelContext)
        dismiss()
    }

    private func deleteIntake() {
        if let id = intake.debtTaskId,
           let task = allTasks.first(where: { $0.id == id }),
           task.status.countsAsDebt {
            WCSyncService.shared.sendDeleteTask(taskId: task.id)
            if let fileName = task.foodImageFileName {
                FoodImageStore.delete(fileName: fileName)
            }
            modelContext.delete(task)
        }
        if let fileName = intake.foodImageFileName {
            FoodImageStore.delete(fileName: fileName)
        }
        modelContext.delete(intake)
        try? modelContext.save()
        WCSyncService.shared.pushTodayIntakeContext(modelContext: modelContext)
        dismiss()
    }

    private var deleteMessage: String {
        var msg = "「\(intake.foodEmoji) \(intake.foodName) · \(intake.estimatedCalories) kcal」"
        if let id = intake.debtTaskId,
           let task = allTasks.first(where: { $0.id == id }),
           task.status.countsAsDebt {
            msg += "\n关联的磨平任务（\(task.status.displayName)）也会一并删除。"
        }
        return msg
    }

    // MARK: - Helpers

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Local helpers

private struct PendingSync: Identifiable {
    let id = UUID()
    let task: DebtTask
}
