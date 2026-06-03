import SwiftUI
import SwiftData
import LevelItShared

/// 运动容器 — 模式选择 → Workout → Completion
struct WatchWorkoutContainerView: View {
    @Bindable var task: DebtTask
    var popToRoot: () -> Void

    @State private var phase: WorkoutPhase?

    enum WorkoutPhase {
        case modeSelect
        case workout
        case completion
    }

    var body: some View {
        Group {
            switch currentPhase {
            case .modeSelect:
                WatchWorkoutModeSelectView(task: task) { selectedMode in
                    task.taskMode = selectedMode
                    task.estimatedMinutes = CalorieCalculator.calculateMinutes(
                        calories: task.estimatedCalories, mode: selectedMode
                    )
                    phase = .workout
                }
            case .workout:
                WatchWorkoutView(task: task) {
                    phase = .completion
                }
            case .completion:
                WatchCompletionView(task: task) {
                    popToRoot()
                }
            }
        }
    }

    /// 根据任务状态决定初始阶段
    private var currentPhase: WorkoutPhase {
        if let phase { return phase }
        // 已暂停或进行中 → 直接恢复运动 (不重新选模式)
        if task.status == .inProgress || task.status == .paused {
            return .workout
        }
        // 已完成 → 直接进入完成页
        if task.status == .completed {
            return .completion
        }
        // 已经选过模式的任务 → 直接进入运动 (iPhone 创建或 Watch Quick Add)
        return .workout
    }
}

/// 运动前的模式选择
struct WatchWorkoutModeSelectView: View {
    let task: DebtTask
    var onSelect: (TaskMode) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                // 任务信息
                HStack(spacing: 6) {
                    Text(task.foodEmoji).font(.title3)
                    Text(task.foodName).font(.caption.weight(.medium))
                    Text("\(task.estimatedCalories)kcal")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                // 运动类型列表
                ForEach(TaskMode.allByIntensity, id: \.self) { mode in
                    Button {
                        WatchHapticManager.tap()
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
                                HStack(spacing: 4) {
                                    Text("\(CalorieCalculator.calculateMinutes(calories: task.estimatedCalories, mode: mode))分钟")
                                        .font(.caption2)
                                    if mode.isIndoor {
                                        Text("室内")
                                            .font(.system(size: 8))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(.blue.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // 强度点
                            HStack(spacing: 2) {
                                ForEach(0..<5) { i in
                                    Circle()
                                        .fill(Double(i) / 5.0 < mode.intensity ? Color.orange : Color.gray.opacity(0.3))
                                        .frame(width: 4, height: 4)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("选择运动")
    }
}
