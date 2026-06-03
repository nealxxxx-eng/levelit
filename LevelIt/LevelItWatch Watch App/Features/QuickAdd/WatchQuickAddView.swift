import SwiftUI
import SwiftData
import LevelItShared

struct WatchQuickAddView: View {
    @Environment(\.modelContext) private var modelContext
    var onTaskCreated: (DebtTask) -> Void

    @State private var showCustom = false
    @State private var customKcal: Double = 200
    @State private var selectedFood: PresetFood?
    @State private var showModeSelect = false

    var body: some View {
        if showModeSelect, let food = selectedFood {
            // 运动模式选择
            WatchModeSelectView(food: food) { mode in
                createAndStart(name: food.name, emoji: food.emoji, kcal: food.estimatedCalories, mode: mode)
            }
        } else {
            // 食物选择
            foodList
        }
    }

    private var foodList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(PresetFoodLibrary.watchQuickPicks) { food in
                    Button {
                        selectedFood = food
                        showModeSelect = true
                        WatchHapticManager.tap()
                    } label: {
                        HStack {
                            Text(food.emoji).font(.title3)
                            Text(food.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text("\(food.estimatedCalories)").font(.caption.weight(.bold))
                            Text("kcal").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider().padding(.vertical, 4)

                if showCustom {
                    customKcalInput
                } else {
                    Button {
                        showCustom = true
                        WatchHapticManager.tap()
                    } label: {
                        Label("自定义热量", systemImage: "plus").font(.caption)
                    }
                }
            }
        }
        .navigationTitle("快速接单")
    }

    private var customKcalInput: some View {
        VStack(spacing: 8) {
            Text("\(Int(customKcal))")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
            Text("kcal").font(.caption).foregroundStyle(.secondary)
            Text("转动表冠调节").font(.caption2).foregroundStyle(.tertiary)

            Button("确定") {
                let food = PresetFood(name: "自定义", emoji: "🍽️", category: .snack, estimatedCalories: Int(customKcal))
                selectedFood = food
                showModeSelect = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .focusable()
        .digitalCrownRotation($customKcal, from: 50, through: 2000, by: 10, sensitivity: .medium)
    }

    private func createAndStart(name: String, emoji: String, kcal: Int, mode: TaskMode) {
        WatchHapticManager.tap()
        let task = DebtTask(
            foodName: name, foodEmoji: emoji,
            estimatedCalories: kcal, taskMode: mode, source: .watch
        )
        modelContext.insert(task)
        if let stats = try? modelContext.fetch(FetchDescriptor<UserStats>()).first {
            stats.totalTasksCreated += 1
        }
        try? modelContext.save()
        WatchSyncReceiver.shared.sendTask(task)
        onTaskCreated(task)
    }
}

/// Watch 运动模式选择页
struct WatchModeSelectView: View {
    @Query private var allTasks: [DebtTask]
    let food: PresetFood
    var onSelect: (TaskMode) -> Void

    private var frequentModes: [TaskMode] {
        var counts: [TaskMode: Int] = [:]
        for task in allTasks {
            counts[task.taskMode, default: 0] += 1
        }
        let sorted = counts.sorted { $0.value > $1.value }.map(\.key)
        return Array(sorted.prefix(3))
    }

    private var hasFrequent: Bool { frequentModes.count >= 3 }

    private var sortedModes: [TaskMode] {
        if hasFrequent {
            let top = frequentModes
            let rest = TaskMode.allByIntensity.filter { !top.contains($0) }
            return top + rest
        }
        return TaskMode.allByIntensity
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("\(food.emoji) \(food.name)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(Array(sortedModes.enumerated()), id: \.element) { index, mode in
                    if hasFrequent && index == 0 {
                        Text("常用")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if hasFrequent && index == frequentModes.count {
                        Divider().padding(.vertical, 2)
                    }

                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.iconName)
                                .font(.body)
                                .foregroundStyle(.orange)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.displayName)
                                    .font(.caption.weight(.medium))
                                Text("\(CalorieCalculator.calculateMinutes(calories: food.estimatedCalories, mode: mode))分钟")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("选择运动")
    }
}
