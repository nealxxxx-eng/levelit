import SwiftUI
import SwiftData
import LevelItShared

struct TaskModeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [DebtTask]
    @Query private var allIntakes: [MealIntake]
    let analysisResult: FoodAnalysisResult
    let intakeId: String?
    var onTaskCreated: (DebtTask) -> Void

    @State private var showAllModes = false

    init(
        analysisResult: FoodAnalysisResult,
        intakeId: String? = nil,
        onTaskCreated: @escaping (DebtTask) -> Void
    ) {
        self.analysisResult = analysisResult
        self.intakeId = intakeId
        self.onTaskCreated = onTaskCreated
    }

    /// 统计历史使用频率最高的 3 种模式
    private var frequentModes: [TaskMode] {
        var counts: [TaskMode: Int] = [:]
        for task in allTasks {
            counts[task.taskMode, default: 0] += 1
        }
        let sorted = counts.sorted { $0.value > $1.value }.map(\.key)
        return Array(sorted.prefix(3))
    }

    /// 是否有足够的常用数据（至少用过 3 种不同模式）
    private var hasFrequent: Bool { frequentModes.count >= 3 }

    /// 顶部显示的模式
    private var topModes: [TaskMode] {
        hasFrequent ? frequentModes : TaskMode.basicModes
    }

    /// 剩余模式
    private var remainingModes: [TaskMode] {
        TaskMode.allByIntensity.filter { !topModes.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                VStack(spacing: DS.Spacing.sm) {
                    Text("选择还法")
                        .font(.title2.weight(.bold))
                    Text("\(analysisResult.foodEmoji) \(analysisResult.foodName) · \(analysisResult.estimatedCalories) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if hasFrequent {
                    Text("常用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(topModes, id: \.self) { mode in
                    modeCard(mode)
                }

                // 更多运动类型
                Button {
                    withAnimation { showAllModes.toggle() }
                } label: {
                    HStack {
                        Text(showAllModes ? "收起" : "更多运动类型")
                            .font(.subheadline)
                        Image(systemName: showAllModes ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(DS.Colors.accent)
                }

                if showAllModes {
                    ForEach(remainingModes, id: \.self) { mode in
                        modeCard(mode)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("选择模式")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func modeCard(_ mode: TaskMode) -> some View {
        let minutes = CalorieCalculator.calculateMinutes(
            calories: analysisResult.estimatedCalories,
            mode: mode
        )

        return Button {
            createTask(mode: mode)
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Image(systemName: mode.iconName)
                        .font(.title2)
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName)
                            .font(.headline)
                        Text(mode.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("\(minutes)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("分钟")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 强度指示条
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.Colors.accent.opacity(0.3))
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DS.Colors.accent)
                                .frame(width: geo.size.width * mode.intensity, height: 6)
                        }
                }
                .frame(height: 6)

                if mode.isIndoor {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 8))
                        Text("室内")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private func createTask(mode: TaskMode) {
        let task = DebtTask(
            foodName: analysisResult.foodName,
            foodEmoji: analysisResult.foodEmoji,
            estimatedCalories: analysisResult.estimatedCalories,
            taskMode: mode,
            source: .iPhone
        )

        // 保存食物照片到本地
        if let imageData = analysisResult.imageData {
            if let fileName = FoodImageStore.save(data: imageData, taskId: task.id) {
                task.foodImageFileName = fileName
            }
        }

        modelContext.insert(task)

        // 回填 MealIntake.debtTaskId（若上游传了 intakeId）
        if let intakeId = intakeId,
           let intake = allIntakes.first(where: { $0.id == intakeId }) {
            intake.debtTaskId = task.id
        }

        var stats = try? modelContext.fetch(FetchDescriptor<UserStats>()).first
        if stats == nil {
            let newStats = UserStats()
            modelContext.insert(newStats)
            stats = newStats
        }
        stats?.totalTasksCreated += 1

        TaskStateMachine.transition(task, to: .synced)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return
        }
        WCSyncService.shared.sendTaskSnapshot(task)
        onTaskCreated(task)
    }
}
