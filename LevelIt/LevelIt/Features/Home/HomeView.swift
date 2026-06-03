import SwiftUI
import SwiftData
import LevelItShared

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]
    @Query(sort: \MealIntake.takenAt, order: .reverse) private var allIntakes: [MealIntake]
    @Query private var stats: [UserStats]

    @State private var settledNotification: DebtTask?
    @State private var taskToDelete: DebtTask?
    @State private var currentPage = 1  // 0=统计 1=首页 2=今日

    private var store: HealthKitDataStore { .shared }
    private var currentStats: UserStats? { stats.first }

    private var pendingTasks: [DebtTask] {
        allTasks.filter { $0.isPendingForDay() }
    }

    private var availableExternalWorkouts: [HealthKitImportService.ImportableWorkout] {
        store.todayExternalWorkouts.filter { !ImportedWorkoutLedger.isImported($0.id.uuidString, in: modelContext) }
    }

    private var pendingKcal: Int {
        pendingTasks.reduce(0) { $0 + max(0, $1.estimatedCalories - $1.burnedCalories) }
    }

    private var todaySettled: Int {
        let calendar = Calendar.current
        return allTasks.filter {
            $0.status == .settled &&
            calendar.isDateInToday($0.completedAt ?? .distantPast)
        }.count
    }

    /// 今日已记录摄入（只统计用户拍照/手动记录过的内容，不代表全天完整摄入）
    private var todayIntakeKcal: Int {
        MealIntakeAggregator.dailyTotalKcal(from: allIntakes, on: Date())
    }

    /// 今日摄入条目（按时间倒序）
    private var todayIntakes: [MealIntake] {
        let cal = Calendar.current
        return allIntakes.filter { cal.isDateInToday($0.takenAt) }
    }

    private var pageTitle: String {
        switch currentPage {
        case 0: return "数据统计"
        case 2: return "今日"
        default: return "磨平"
        }
    }

    var body: some View {
        ZStack {
            TabView(selection: $currentPage) {
                StatsView().tag(0)
                homeContent.tag(1)
                TodayView().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            if currentPage == 1, let task = settledNotification {
                settledBanner(task)
            }
        }
        .navigationTitle(pageTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation { currentPage = 0 }
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(currentPage == 0 ? DS.Colors.accent : .primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        withAnimation { currentPage = 2 }
                    } label: {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(currentPage == 2 ? DS.Colors.accent : .primary)
                    }
                    NavigationLink(value: AppRoute.foodWall) {
                        Image(systemName: "square.grid.2x2.fill")
                    }
                    NavigationLink(value: AppRoute.taskList) {
                        Image(systemName: "list.bullet")
                    }
                    NavigationLink(value: AppRoute.settings) {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .onAppear {
            checkForNewSettlements()
        }
        .task(id: scenePhase) {
            // 仅前台时轮询检查新结清通知, 后台暂停避免耗电
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                checkForNewSettlements()
            }
        }
        .task(id: scenePhase) {
            // 每次回到前台时刷新今日外部运动 (系统运动在后台完成后能即时显示)
            guard scenePhase == .active, !pendingTasks.isEmpty else { return }
            await store.refreshTodayWorkouts()
        }
        .alert("确认删除", isPresented: .init(
            get: { taskToDelete != nil },
            set: { if !$0 { taskToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let task = taskToDelete { deleteTask(task) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let task = taskToDelete {
                Text("删除「\(task.foodEmoji) \(task.foodName)」？此操作不可撤销。")
            }
        }
    }

    // MARK: - 首页内容

    private var homeContent: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                if pendingTasks.isEmpty {
                    emptyState
                    ctaButtons
                    if !todayIntakes.isEmpty {
                        todayIntakePreview
                    }
                } else {
                    debtHeader
                    statsRow

                    if !availableExternalWorkouts.isEmpty || CalorieBalance.availableCalories(in: modelContext) > 0 || NaturalAllowance.available > 0 {
                        workoutImportBanner
                    }

                    if NaturalAllowance.dailyTotal > 0 {
                        naturalAllowanceBadge
                    }

                    ctaButtons

                    if !todayIntakes.isEmpty {
                        todayIntakePreview
                    }

                    pendingSection
                }
            }
            .padding()
        }
    }

    // MARK: - 今日欠债大字

    private var debtHeader: some View {
        VStack(spacing: DS.Spacing.sm) {
            Text("\(pendingKcal)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(debtColor)
                .contentTransition(.numericText())

            Text("kcal 待磨平")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
    }

    private var debtColor: Color {
        switch pendingKcal {
        case ..<200:  return .green
        case ..<400:  return .yellow
        case ..<600:  return .orange
        default:      return .red
        }
    }

    // MARK: - 统计栏

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: "\(todayIntakeKcal)", label: "已记录摄入")
            Divider().frame(height: 32)
            statItem(value: "\(todaySettled)", label: "今日结清")
            Divider().frame(height: 32)
            statItem(value: "\(currentStats?.currentStreak() ?? 0)天", label: "连续磨平")
            Divider().frame(height: 32)
            statItem(value: badgeText, label: "当前徽章")
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var badgeText: String {
        let streak = currentStats?.currentStreak() ?? 0
        return AchievementType.highestAchievable(forStreak: streak)?.rawValue ?? "--"
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - CTA 按钮

    private var ctaButtons: some View {
        VStack(spacing: DS.Spacing.md) {
            NavigationLink(value: AppRoute.scan) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("记录一口，磨平一点")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)

                            Text("拍下食物，AI 会估热量并接上今日磨平计划")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.82))
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.18))
                                .frame(width: 58, height: 58)
                            Image(systemName: "camera.aperture")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }

                    HStack(spacing: DS.Spacing.sm) {
                        flowPill("拍一下", icon: "camera.fill")
                        flowDivider
                        flowPill("AI 估热量", icon: "sparkles")
                        flowDivider
                        flowPill("生成任务", icon: "figure.run")
                    }

                    HStack {
                        Text("打开磨平镜头")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .foregroundStyle(.white)
                }
                .padding(DS.Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            Color.orange,
                            Color(red: 0.95, green: 0.32, blue: 0.18),
                            Color(red: 0.54, green: 0.20, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 150, height: 150)
                        .offset(x: 46, y: 54)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .shadow(color: Color.orange.opacity(0.25), radius: 18, y: 10)
            }
            .buttonStyle(.plain)

            NavigationLink(value: AppRoute.manualSelect) {
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.headline)
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 34, height: 34)
                        .background(DS.Colors.accent.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("不方便拍照？手动选一个")
                            .font(.headline)
                        Text("奶茶、零食、快餐可以快速记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(DS.Colors.cardBackground)
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func flowPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.white.opacity(0.16))
        .clipShape(Capsule())
    }

    private var flowDivider: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.58))
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Text("今日无债")
                .font(.title3.weight(.bold))
            Text("无债一身轻")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("吃了什么？拍一下")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
    }

    // MARK: - 今日摄入预览（主页快速可见）

    private var todayIntakePreview: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.red)
                Text("今日已记录摄入")
                    .font(.headline)
                Spacer()
                Text("\(todayIntakeKcal) kcal · \(todayIntakes.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(todayIntakes.prefix(3), id: \.id) { intake in
                NavigationLink(value: AppRoute.mealIntakeEdit(intake)) {
                    HStack(spacing: DS.Spacing.md) {
                        Text(intake.foodEmoji)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(intake.foodName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text("\(intake.mealKind.emoji) \(intake.mealKind.displayName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                intakeVerdictTag(intake.verdictKind)
                            }
                        }

                        Spacer()

                        Text("\(intake.estimatedCalories)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.red)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            if todayIntakes.count > 3 {
                Button {
                    withAnimation { currentPage = 2 }
                } label: {
                    HStack {
                        Text("查看全部 \(todayIntakes.count) 条")
                            .font(.caption.weight(.medium))
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(DS.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func intakeVerdictTag(_ kind: MealVerdictKind) -> some View {
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
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - 待磨平列表

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("待磨平")
                .font(.headline)

            ForEach(pendingTasks.prefix(5), id: \.id) { task in
                NavigationLink(value: AppRoute.taskDetail(task)) {
                    HStack(spacing: DS.Spacing.md) {
                        Text(task.foodEmoji).font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.foodName).font(.body.weight(.medium))
                            HStack(spacing: 4) {
                                Text(task.status.displayName)
                                    .font(.caption)
                                if task.status == .inProgress {
                                    Image(systemName: "applewatch")
                                        .font(.caption2)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(task.estimatedCalories) kcal")
                                .font(.subheadline.weight(.medium))
                            if task.progressPercent > 0 {
                                Text("\(task.progressPercent)%")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Colors.accent)
                            } else {
                                Text(task.taskLevel.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(task.taskLevel.color.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        taskToDelete = task
                    } label: {
                        Label("删除任务", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - 结清通知卡片

    private func settledBanner(_ task: DebtTask) -> some View {
        VStack {
            NavigationLink(value: AppRoute.result(task)) {
                HStack(spacing: DS.Spacing.md) {
                    Text(task.foodEmoji).font(.title2)
                    VStack(alignment: .leading) {
                        Text("\(task.foodName) 已结清!")
                            .font(.subheadline.weight(.bold))
                        Text("点击查看详情")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.green.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { settledNotification = nil }
            }
        }
    }

    // MARK: - 外部运动导入提示

    private var workoutImportBanner: some View {
        let workoutCal = availableExternalWorkouts.reduce(0) { $0 + $1.calories }
        let balanceCal = CalorieBalance.availableCalories(in: modelContext)
        let naturalCal = NaturalAllowance.available
        let totalCal = workoutCal + balanceCal + naturalCal
        return NavigationLink(value: AppRoute.workoutImport) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "heart.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("可抵扣 \(totalCal) kcal")
                        .font(.subheadline.weight(.bold))

                    let parts = [
                        workoutCal > 0 ? "运动 \(workoutCal)" : nil,
                        balanceCal > 0 ? "余额 \(balanceCal)" : nil,
                        naturalCal > 0 ? "自然消耗 \(naturalCal)" : nil
                    ].compactMap { $0 }

                    if !parts.isEmpty {
                        Text(parts.joined(separator: " + "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("点击抵扣到待磨平任务")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 自然消耗余额标签

    private var naturalAllowanceBadge: some View {
        let profile = UserProfileStore.current
        let available = NaturalAllowance.available
        let total = NaturalAllowance.dailyTotal

        return HStack(spacing: DS.Spacing.md) {
            Image(systemName: "bolt.heart.fill")
                .font(.title3)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("今日自然消耗")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("\(available)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.green)
                    Text("/ \(total) kcal")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let p = profile {
                Text("BMR \(p.bmr)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(DS.Spacing.md)
        .background(.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - 删除任务

    private func deleteTask(_ task: DebtTask) {
        WCSyncService.shared.sendDeleteTask(taskId: task.id)
        if let fileName = task.foodImageFileName {
            FoodImageStore.delete(fileName: fileName)
        }
        modelContext.delete(task)
        try? modelContext.save()
    }

    // MARK: - 结清检查

    @State private var notifiedTaskIds: Set<String> = []
    @State private var launchTime = Date()

    private func checkForNewSettlements() {
        if let recent = allTasks.first(where: {
            $0.status == .settled &&
            ($0.completedAt ?? .distantPast) > launchTime &&
            !notifiedTaskIds.contains($0.id)
        }) {
            notifiedTaskIds.insert(recent.id)
            withAnimation {
                settledNotification = recent
            }
        }
    }
}
