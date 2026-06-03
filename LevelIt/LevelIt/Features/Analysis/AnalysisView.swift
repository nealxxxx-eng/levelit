import SwiftUI
import SwiftData
import LevelItShared

struct AnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.popToRoot) private var popToRoot
    let originalResult: FoodAnalysisResult
    var onNavigate: (AppRoute) -> Void

    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]
    @Query(sort: \MealIntake.takenAt, order: .reverse) private var allIntakes: [MealIntake]

    @State private var diners: Int = 1
    @State private var showShareSheet = false
    @State private var hasConfirmedShare = false

    /// 实际吃了多少（占单份的比例 0.0–1.0）。1.0 = 全吃完。
    @State private var actualPortion: Double = 1.0

    /// MealClassifier 触发的 Alert 数据
    @State private var pendingAlert: AnalysisAlert?

    /// 防重复点击 + 防 Alert 关闭/系统返回手势后再次写 MealIntake
    /// 一旦本次 AnalysisView 实例 classify 过一次就锁住按钮，需要重新拍照才能再触发
    @State private var hasClassified = false

    /// 分餐后单份热量（不含实际摄入比例）
    private var dinerAdjusted: Int {
        max(AppConstants.minCalories, originalResult.estimatedCalories / diners)
    }

    /// 最终实际摄入热量 = 单份 × 实际比例
    private var actualKcal: Int {
        max(AppConstants.minCalories, Int(Double(dinerAdjusted) * actualPortion))
    }

    private var effectiveResult: FoodAnalysisResult {
        let needsSuffix = diners > 1 || actualPortion < 1.0
        guard needsSuffix else { return originalResult }
        let suffix: String = {
            if diners > 1 && actualPortion < 1.0 {
                return " (1/\(diners)份 × \(Int(actualPortion * 100))%)"
            } else if diners > 1 {
                return " (1/\(diners)份)"
            } else {
                return " (\(Int(actualPortion * 100))%)"
            }
        }()
        return FoodAnalysisResult(
            foodName: "\(originalResult.foodName)\(suffix)",
            foodEmoji: originalResult.foodEmoji,
            estimatedCalories: actualKcal,
            imageData: originalResult.imageData
        )
    }

    private var level: TaskLevel {
        TaskLevel.from(calories: actualKcal)
    }

    private var isSharedMeal: Bool {
        originalResult.estimatedCalories > AppConstants.sharedMealThreshold
    }

    /// 查找历史上同名食物的最近一次已完成任务
    private var priorRecord: DebtTask? {
        let name = originalResult.foodName
        return allTasks.first { task in
            task.status == .settled &&
            task.durationSeconds > 0 &&
            (task.foodName.contains(name) || name.contains(task.foodName))
        }
    }

    init(result: FoodAnalysisResult, onNavigate: @escaping (AppRoute) -> Void) {
        self.originalResult = result
        self.onNavigate = onNavigate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                foodCard

                // 前科记录
                if let prior = priorRecord {
                    priorRecordBanner(prior)
                }

                calorieInfo

                // 分餐调整卡（高热量时显示）
                if isSharedMeal {
                    shareAdjustCard
                }

                portionAdjustCard

                modePreview

                Button {
                    classifyAndNavigate()
                } label: {
                    Text(hasClassified ? "已记录此次摄入" : "生成磨平任务")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(hasClassified
                                    ? Color.gray.opacity(0.4)
                                    : DS.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                .disabled(hasClassified)
            }
            .padding()
        }
        .navigationTitle("分析结果")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            shareSheet
        }
        .onAppear {
            if isSharedMeal && !hasConfirmedShare {
                showShareSheet = true
            }
        }
        .alert(item: $pendingAlert) { payload in
            Alert(
                title: Text("\(payload.kind.emoji) 本餐\(payload.kind.displayName)\(payload.verdictKind.displayName)"),
                message: Text("本餐合计 \(payload.actualKcal) kcal，已记录到今日摄入，即将返回首页。"),
                dismissButton: .default(Text("好的")) {
                    popToRoot()
                }
            )
        }
    }

    // MARK: - 餐次分流

    private func classifyAndNavigate() {
        // 防重复：本视图实例只允许 classify 一次
        guard !hasClassified else { return }
        hasClassified = true

        let now = Date()
        let profile = UserProfileStore.current
        let config = MealQuotaConfigStore.current
        let thisKcal = effectiveResult.estimatedCalories

        // 1. 先按"现在的时间"判定餐次
        let kindNow = config.mealKind(at: now)

        // 2. 累加同餐次同日已记录的摄入，作为 MealClassifier 的 cumulative 输入
        let alreadyKcal = MealIntakeAggregator.cumulativeKcal(
            kind: kindNow, from: allIntakes, on: now
        )
        let cumulative = alreadyKcal + thisKcal

        let verdict = MealClassifier.classify(
            cumulativeKcal: cumulative,
            previousCumulativeKcal: alreadyKcal,
            at: now,
            profile: profile,
            config: config
        )

        // 3. 写入 MealIntake（无论判定结果都记录这次摄入事实）
        let intake = MealIntake(
            foodName: effectiveResult.foodName,
            foodEmoji: effectiveResult.foodEmoji,
            estimatedCalories: thisKcal,
            originalCalories: originalResult.estimatedCalories,
            diners: diners,
            takenAt: now,
            mealKind: kindNow,
            verdictKind: verdict.kind
        )
        // 食物照片落本地 + 关联到 intake
        if let imageData = effectiveResult.imageData,
           let fileName = FoodImageStore.save(data: imageData, taskId: intake.id) {
            intake.foodImageFileName = fileName
        }
        modelContext.insert(intake)
        try? modelContext.save()
        WCSyncService.shared.pushTodayIntakeContext(modelContext: modelContext)

        // 4. 根据 verdict 决定下一步
        switch verdict {
        case .snack:
            onNavigate(.taskMode(result: effectiveResult, intakeId: intake.id))

        case .bufferedSnack(let actual, _):
            pendingAlert = AnalysisAlert(
                kind: .snack, actualKcal: actual, verdictKind: .snackBuffered
            )

        case .overSnack(_, _, let gap):
            let taskResult = FoodAnalysisResult(
                foodName: "\(effectiveResult.foodName)（加餐超额）",
                foodEmoji: effectiveResult.foodEmoji,
                estimatedCalories: gap,
                imageData: effectiveResult.imageData
            )
            onNavigate(.taskMode(result: taskResult, intakeId: intake.id))

        case .overMeal(let kind, let actual, _, let gap):
            onNavigate(.mealOverConfirm(
                result: effectiveResult,
                mealKind: kind,
                actualKcal: actual,
                gapKcal: gap,
                accumulatedBefore: alreadyKcal,
                intakeId: intake.id
            ))

        case .normalMeal(let kind, let actual, _):
            pendingAlert = AnalysisAlert(
                kind: kind, actualKcal: actual, verdictKind: .normal
            )

        case .underMeal(let kind, let actual, _, _):
            pendingAlert = AnalysisAlert(
                kind: kind, actualKcal: actual, verdictKind: .under
            )
        }
    }

    // MARK: - Food Card

    private var foodCard: some View {
        VStack(spacing: DS.Spacing.md) {
            Text(originalResult.foodEmoji)
                .font(.system(size: 80))

            Text(originalResult.foodName)
                .font(.title2.weight(.bold))

            if diners > 1 {
                Text("你的份额：1/\(diners)")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DS.Colors.accent.opacity(0.15))
                    .foregroundStyle(DS.Colors.accent)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.xl)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
    }

    // MARK: - 前科记录

    private func priorRecordBanner(_ task: DebtTask) -> some View {
        let minutes = task.durationSeconds / 60
        return HStack(spacing: DS.Spacing.md) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("上次这份\(task.foodName)你花了 \(minutes) 分钟磨平")
                    .font(.subheadline.weight(.medium))
                Text("还来？")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Calorie Info

    private var calorieInfo: some View {
        VStack(spacing: DS.Spacing.md) {
            if originalResult.estimatedCalories != actualKcal {
                HStack(spacing: DS.Spacing.sm) {
                    Text("\(originalResult.estimatedCalories)")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(actualKcal)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(level.color)
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: DS.Spacing.md) {
                levelBadge
                riskLabel
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var levelBadge: some View {
        Text(level.displayName)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(level.color.opacity(0.2))
            .foregroundStyle(level.color)
            .clipShape(Capsule())
    }

    private var riskLabel: some View {
        let text: String = switch level {
        case .green:  "不费劲"
        case .yellow: "得动一动"
        case .orange: "有点挑战"
        case .red:    "硬核债务"
        }
        return Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Portion Adjust Card

    /// 实际摄入量调整：识别热量是"这份食物的总量"，但用户可能没全吃完。
    private var portionAdjustCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Image(systemName: "fork.knife.circle.fill")
                    .foregroundStyle(DS.Colors.accent)
                Text("实际吃了多少")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(actualPortion * 100))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(DS.Colors.accent)
                    .contentTransition(.numericText())
            }

            Slider(value: $actualPortion, in: 0.1...1.0, step: 0.05)
                .tint(DS.Colors.accent)

            HStack(spacing: DS.Spacing.sm) {
                portionQuickButton("全吃", value: 1.0)
                portionQuickButton("3/4", value: 0.75)
                portionQuickButton("一半", value: 0.5)
                portionQuickButton("一口", value: 0.25)
            }

            if actualPortion < 1.0 {
                let saved = dinerAdjusted - actualKcal
                Text("少摄入了 \(saved) kcal")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func portionQuickButton(_ title: String, value: Double) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                actualPortion = value
            }
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(abs(actualPortion - value) < 0.001
                            ? DS.Colors.accent.opacity(0.2)
                            : Color.gray.opacity(0.08))
                .foregroundStyle(abs(actualPortion - value) < 0.001
                                 ? DS.Colors.accent
                                 : .primary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
    }

    // MARK: - Share Adjust Card (inline)

    private var shareAdjustCard: some View {
        VStack(spacing: DS.Spacing.md) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(DS.Colors.accent)
                Text(diners > 1 ? "已设为 \(diners) 人分餐" : "这是多人分享的餐吗？")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    showShareSheet = true
                } label: {
                    Text(diners > 1 ? "修改" : "调整")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DS.Colors.accent.opacity(0.15))
                        .foregroundStyle(DS.Colors.accent)
                        .clipShape(Capsule())
                }
            }

            if diners == 1 {
                Text("AI 识别到 \(originalResult.estimatedCalories) kcal，超出单人一餐正常范围，建议设置分餐人数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(DS.Colors.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Share Sheet

    private var shareSheet: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xl) {
                // 标题区
                VStack(spacing: DS.Spacing.sm) {
                    Text("🍽️")
                        .font(.system(size: 48))
                    Text("几个人分享这顿饭？")
                        .font(.title3.weight(.bold))
                    Text("总热量 \(originalResult.estimatedCalories) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, DS.Spacing.lg)

                // 快捷选项
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: DS.Spacing.md) {
                    ForEach([1, 2, 3, 4, 5, 6, 8, 10], id: \.self) { n in
                        shareOption(n)
                    }
                }
                .padding(.horizontal)

                // 预览
                VStack(spacing: DS.Spacing.sm) {
                    let preview = max(AppConstants.minCalories, originalResult.estimatedCalories / max(1, diners))
                    let previewLevel = TaskLevel.from(calories: preview)

                    Text("你的份额")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(preview)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(previewLevel.color)
                        Text("kcal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(previewLevel.displayName)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(previewLevel.color.opacity(0.2))
                        .foregroundStyle(previewLevel.color)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(DS.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                .padding(.horizontal)

                Spacer()

                // 确认按钮
                Button {
                    hasConfirmedShare = true
                    showShareSheet = false
                } label: {
                    Text(diners > 1 ? "确认 1/\(diners) 份" : "就是我一个人吃的")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("分餐设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳过") {
                        diners = 1
                        hasConfirmedShare = true
                        showShareSheet = false
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func shareOption(_ n: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                diners = n
            }
        } label: {
            VStack(spacing: 4) {
                Text(n == 1 ? "独享" : "\(n)人")
                    .font(.headline)
                if n > 1 {
                    Text("1/\(n)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(diners == n ? DS.Colors.accent : DS.Colors.cardBackground)
            .foregroundStyle(diners == n ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }

    // MARK: - Mode Preview

    private var modePreview: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("磨平需要")
                .font(.headline)

            ForEach(CalorieCalculator.calculateAllModes(calories: actualKcal), id: \.mode) { item in
                HStack {
                    Image(systemName: item.mode.iconName)
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 24)
                    Text(item.mode.displayName)
                        .font(.body)
                    Spacer()
                    Text("约 \(item.minutes) 分钟")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }
}

// MARK: - Alert Payload

private struct AnalysisAlert: Identifiable {
    let id = UUID()
    let kind: MealKind
    let actualKcal: Int
    let verdictKind: MealVerdictKind
}
