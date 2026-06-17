import SwiftUI
import SwiftData
import LevelItShared

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]
    @Query(sort: \MealIntake.takenAt, order: .reverse) private var allIntakes: [MealIntake]
    @Query(sort: \PKChallenge.createdAt, order: .reverse) private var allChallenges: [PKChallenge]

    @State private var intakeToDelete: MealIntake?

    private let calendar = Calendar.current
    private var store: HealthKitDataStore { .shared }

    // MARK: - 今日数据源

    private var todayTasks: [DebtTask] {
        allTasks.filter { calendar.isDateInToday($0.createdAt) }
    }

    private var todayIntakes: [MealIntake] {
        allIntakes.filter { calendar.isDateInToday($0.takenAt) }
    }

    /// 今日已记录摄入：只包含用户拍照/手动记录过的食物，不代表全天完整摄入。
    private var todayIntake: Int {
        MealIntakeAggregator.dailyTotalKcal(from: allIntakes, on: Date())
    }

    private var todayBurned: Int {
        todayWorkouts.reduce(0) { $0 + $1.calories }
    }

    private var todayDurationMinutes: Int {
        Int(todayWorkouts.reduce(0.0) { $0 + $1.duration } / 60)
    }

    private var todayWorkouts: [HealthKitImportService.WorkoutSummary] {
        store.todayWorkoutSummaries
    }

    private var activePKCount: Int {
        allChallenges.filter { $0.status == .invited || $0.status == .accepted }.count
    }

    private var todaySettled: Int {
        todayTasks.filter { $0.status == .settled || $0.status == .completed }.count
    }

    private var todayPending: Int {
        todayTasks.filter { $0.status.countsAsDebt }.count
    }

    private var pendingDebtKcal: Int {
        todayTasks
            .filter { $0.status.countsAsDebt }
            .reduce(0) { $0 + max(0, $1.targetBurnCalories - $1.burnedCalories) }
    }

    private var snackBufferTotal: Int {
        guard let profile = UserProfileStore.current else { return 0 }
        return MealQuotaConfigStore.current.snackBufferCalories(tdee: profile.tdee)
    }

    private var todaySnackIntake: Int {
        MealIntakeAggregator.dailyTotalKcal(kind: .snack, from: allIntakes, on: Date())
    }

    private var snackBufferUsed: Int {
        min(todaySnackIntake, snackBufferTotal)
    }

    private var snackBufferRemaining: Int {
        max(0, snackBufferTotal - snackBufferUsed)
    }

    private var snackBufferOverage: Int {
        max(0, todaySnackIntake - snackBufferTotal)
    }

    private var snackBufferProgress: Double {
        guard snackBufferTotal > 0 else { return 0 }
        return min(1, Double(snackBufferUsed) / Double(snackBufferTotal))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                todayStatus

                dailySettlementCard

                if !todayIntakes.isEmpty {
                    intakeList
                }

                if !todayWorkouts.isEmpty {
                    workoutList
                }

                todayMetrics

                pkSection
            }
            .padding()
        }
        .task {
            await store.refreshTodayWorkoutSummaries()
        }
        .alert("删除这条记录？", isPresented: .init(
            get: { intakeToDelete != nil },
            set: { if !$0 { intakeToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let intake = intakeToDelete { deleteIntake(intake) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let intake = intakeToDelete {
                Text(deleteAlertMessage(for: intake))
            }
        }
    }

    // MARK: - 今日状态

    private var todayStatus: some View {
        VStack(spacing: DS.Spacing.md) {
            Text(statusEmoji)
                .font(.system(size: 56))

            Text(statusText)
                .font(.title3.weight(.bold))

            Text(statusSubtext)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: DS.Spacing.xl) {
                VStack(spacing: 4) {
                    Text("\(todayIntake)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                    Text("摄入 kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: pendingDebtKcal == 0 ? "checkmark" : "arrow.right")
                    .font(.title3)
                    .foregroundStyle(pendingDebtKcal == 0 ? .green : .orange)

                VStack(spacing: 4) {
                    Text("\(pendingDebtKcal)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.accent)
                    Text("待磨平 kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 每日结算

    private var dailySettlementCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日结算")
                        .font(.headline)
                    Text(settlementHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(settlementBadgeText)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(settlementBadgeColor.opacity(0.15))
                    .foregroundStyle(settlementBadgeColor)
                    .clipShape(Capsule())
            }

            HStack(spacing: 0) {
                settlementMetric(value: "\(todayIntake)", label: "已记录摄入", color: .red)
                Divider().frame(height: 34)
                settlementMetric(value: "\(todayBurned)", label: "任务运动消耗", color: .green)
                Divider().frame(height: 34)
                settlementMetric(value: "\(pendingDebtKcal)", label: "待磨平", color: DS.Colors.accent)
            }

            snackBufferSection
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var snackBufferSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Label("加餐缓冲", systemImage: "cup.and.saucer.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text(snackBufferSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(snackBufferOverage > 0 ? .orange : .secondary)
            }

            ProgressView(value: snackBufferProgress)
                .tint(snackBufferOverage > 0 ? .orange : .green)

            Text(snackBufferDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DS.Spacing.md)
        .background((snackBufferOverage > 0 ? Color.orange : Color.green).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func settlementMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var settlementHint: String {
        if todayIntakes.isEmpty {
            return "拍照或手动记录后，这里会形成今日轻量账本。"
        }
        return "只结算已记录内容，未拍的正餐不会被推断为摄入。"
    }

    private var settlementBadgeText: String {
        if todayIntakes.isEmpty { return "未开始" }
        return pendingDebtKcal == 0 ? "已磨平" : "还差 \(pendingDebtKcal) kcal"
    }

    private var settlementBadgeColor: Color {
        if todayIntakes.isEmpty { return .secondary }
        return pendingDebtKcal == 0 ? .green : .orange
    }

    private var snackBufferSummary: String {
        guard snackBufferTotal > 0 else { return "未设置" }
        return "\(snackBufferUsed)/\(snackBufferTotal) kcal"
    }

    private var snackBufferDetail: String {
        guard snackBufferTotal > 0 else {
            return "完善身高、体重、年龄和活动强度后，可按 TDEE 自动计算每日加餐缓冲。"
        }
        if todaySnackIntake == 0 {
            return "今天还没有记录加餐；饮料、甜品等会先使用这部分缓冲。"
        }
        if snackBufferOverage > 0 {
            return "加餐已超过缓冲 \(snackBufferOverage) kcal，超出的增量会进入待磨平任务。"
        }
        return "加餐仍在缓冲内，剩余 \(snackBufferRemaining) kcal；暂不强制生成运动任务。"
    }

    private var statusEmoji: String {
        if todayIntakes.isEmpty { return "😴" }
        if pendingDebtKcal == 0 { return "💪" }
        if todayPending == 0 && !todayTasks.isEmpty { return "🎉" }
        return "🏃"
    }

    private var statusText: String {
        if todayIntakes.isEmpty { return "今天还没开始" }
        if pendingDebtKcal == 0 && todaySettled > 0 { return "今日已磨平!" }
        if todayPending > 0 { return "还有 \(todayPending) 单待磨平" }
        return "记录中..."
    }

    private var statusSubtext: String {
        if todayIntakes.isEmpty { return "吃了什么？拍一下开始记录。未拍的正餐不会计入全天摄入。" }
        if pendingDebtKcal == 0 { return "当前没有待磨平债务；已记录摄入不代表全天完整摄入。" }
        return "还需消耗 \(pendingDebtKcal) kcal 才能磨平已确认债务"
    }

    // MARK: - 今日摄入清单（基于 MealIntake）

    private var intakeList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("今日已记录摄入")
                    .font(.headline)
                Spacer()
                Text("\(todayIntakes.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(todayIntakes, id: \.id) { intake in
                intakeRow(intake)
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func intakeRow(_ intake: MealIntake) -> some View {
        NavigationLink(value: AppRoute.mealIntakeEdit(intake)) {
            HStack(spacing: DS.Spacing.md) {
                Text(intake.foodEmoji)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(intake.foodName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text("\(intake.mealKind.emoji) \(intake.mealKind.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        verdictTag(intake.verdictKind)
                        Text(timeString(intake.takenAt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(intake.estimatedCalories)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.red)
                    if intake.diners > 1 {
                        Text("1/\(intake.diners) 份")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // 磨平任务关联状态图标
                if let debtTaskId = intake.debtTaskId,
                   let task = allTasks.first(where: { $0.id == debtTaskId }) {
                    taskStatusIcon(for: task)
                } else {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(DS.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                intakeToDelete = intake
            } label: {
                Label("删除记录", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                intakeToDelete = intake
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func verdictTag(_ kind: MealVerdictKind) -> some View {
        let (text, color): (String, Color) = switch kind {
        case .normal:        ("达标", .green)
        case .over:          ("超标", .orange)
        case .under:         ("偏少", .blue)
        case .snack:         ("加餐", .purple)
        case .snackBuffered: ("缓冲内", .green)
        case .snackOver:     ("加餐超额", .orange)
        }
        return Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func taskStatusIcon(for task: DebtTask) -> some View {
        switch task.status {
        case .settled, .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .inProgress:
            Image(systemName: "figure.run")
                .foregroundStyle(DS.Colors.accent)
        case .expired:
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.gray)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.gray)
        case .created, .synced, .paused:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: - 今日运动清单（基于 HealthKit）

    private var workoutList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("今日运动记录")
                    .font(.headline)
                Spacer()
                Text("\(todayWorkouts.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(todayWorkouts, id: \.id) { workout in
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: workout.iconName)
                        .font(.title3)
                        .foregroundStyle(.green)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text("\(workout.durationMinutes) 分钟")
                            Text(workout.source)
                            Text(timeString(workout.startDate))
                            if workout.isLevelIt {
                                Text("磨平")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(DS.Colors.accent.opacity(0.14))
                                    .foregroundStyle(DS.Colors.accent)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(workout.calories)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.green)
                }
                .padding(DS.Spacing.sm)
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 今日指标

    private var todayMetrics: some View {
        HStack(spacing: 0) {
            metricItem(
                icon: "fork.knife",
                value: "\(todayIntakes.count)",
                label: "摄入次数",
                color: .red
            )
            Divider().frame(height: 36)
            metricItem(
                icon: "checkmark.seal.fill",
                value: "\(todaySettled)",
                label: "已结清",
                color: .green
            )
            Divider().frame(height: 36)
            metricItem(
                icon: "clock",
                value: "\(todayDurationMinutes)",
                label: "运动分钟",
                color: DS.Colors.accent
            )
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func metricItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 删除逻辑

    private func deleteAlertMessage(for intake: MealIntake) -> String {
        var msg = "「\(intake.foodEmoji) \(intake.foodName) · \(intake.estimatedCalories) kcal」"
        if let debtTaskId = intake.debtTaskId,
           let task = allTasks.first(where: { $0.id == debtTaskId }),
           task.status.countsAsDebt {
            msg += "\n关联的磨平任务（\(task.status.displayName)）也会一并删除。"
        }
        return msg
    }

    /// 硬删 intake；联级处理关联的 DebtTask（仅未结清/未过期才删）
    private func deleteIntake(_ intake: MealIntake) {
        // 1. 联级删除关联的活跃 DebtTask
        if let debtTaskId = intake.debtTaskId,
           let task = allTasks.first(where: { $0.id == debtTaskId }) {
            // 已 settled / cancelled / expired 的历史不动，保留为账本记录
            if task.status.countsAsDebt {
                WCSyncService.shared.sendDeleteTask(taskId: task.id)
                if let fileName = task.foodImageFileName {
                    FoodImageStore.delete(fileName: fileName)
                }
                modelContext.delete(task)
            }
        }

        // 2. 删 intake 自己的照片
        if let fileName = intake.foodImageFileName {
            FoodImageStore.delete(fileName: fileName)
        }

        // 3. 删 intake 本身
        modelContext.delete(intake)
        try? modelContext.save()
        WCSyncService.shared.pushTodayIntakeContext(modelContext: modelContext)
    }

    // MARK: - 朋友 PK

    private var pkSection: some View {
        NavigationLink(value: AppRoute.pkChallengeCenter) {
            VStack(spacing: DS.Spacing.md) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.title2)
                        .foregroundStyle(DS.Colors.accent)
                    Text("朋友 PK")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(activePKCount > 0 ? "\(activePKCount) 个进行中" : "发起挑战")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DS.Colors.accent.opacity(0.15))
                        .foregroundStyle(DS.Colors.accent)
                        .clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: DS.Spacing.sm) {
                    pkFeatureRow(
                        icon: "flame.fill",
                        title: "对赌模式",
                        desc: "和朋友同时接单，谁先结清谁赢"
                    )
                    pkFeatureRow(
                        icon: "trophy.fill",
                        title: "挑战记录",
                        desc: "保存邀请、目标和进行中的 PK"
                    )
                    pkFeatureRow(
                        icon: "square.and.arrow.up",
                        title: "分享邀请",
                        desc: "生成邀请码，通过微信或系统分享发给朋友"
                    )
                }
            }
            .padding()
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private func pkFeatureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}
