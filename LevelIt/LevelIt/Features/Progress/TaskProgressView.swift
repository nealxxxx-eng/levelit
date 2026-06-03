import SwiftUI
import SwiftData
import LevelItShared

/// iPhone 降级模拟运动 — 仅在无 Watch 配对时使用
struct TaskProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: DebtTask
    @State private var workout = MockWorkoutService()
    @State private var quoteText = ""
    @State private var shownQuoteIndices: Set<Int> = []

    var onCompleted: (DebtTask) -> Void

    private var progress: Double {
        guard task.targetBurnCalories > 0 else { return 0 }
        return min(1.0, Double(task.burnedCalories) / Double(task.targetBurnCalories))
    }

    private var remaining: Int {
        max(0, task.targetBurnCalories - task.burnedCalories)
    }

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            // 降级提示
            HStack {
                Image(systemName: "iphone")
                    .foregroundStyle(.blue)
                Text("iPhone 模拟运动")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())

            progressRing
            statsPanel

            if !quoteText.isEmpty {
                Text(quoteText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
            actionButtons
        }
        .padding()
        .navigationTitle(task.foodName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(workout.isRunning)
        .onAppear { startIfNeeded() }
        .onDisappear { workout.stop() }
        .onChange(of: workout.burnedCalories) { _, _ in updateTask() }
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(DS.Colors.cardBackground, lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(DS.Colors.accent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
            VStack(spacing: 4) {
                Text("\(task.progressPercent)%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("已磨平").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, height: 200)
        .padding(.top)
    }

    private var statsPanel: some View {
        HStack(spacing: 0) {
            statColumn(value: "\(task.burnedCalories)", unit: "kcal", label: "已消耗")
            Divider().frame(height: 40)
            statColumn(value: "\(remaining)", unit: "kcal", label: "剩余")
            Divider().frame(height: 40)
            statColumn(value: formatDuration(workout.durationSeconds), unit: "", label: "用时")
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func statColumn(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.headline).contentTransition(.numericText())
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        Group {
            if !workout.isRunning && (task.status == .created || task.status == .synced) {
                Button {
                    startWorkout()
                } label: {
                    Label("开始磨平 (模拟)", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
            } else if workout.isRunning {
                HStack(spacing: DS.Spacing.md) {
                    Button {
                        if workout.isPaused { workout.resume(); TaskStateMachine.transition(task, to: .inProgress) }
                        else { workout.pause(); TaskStateMachine.transition(task, to: .paused) }
                    } label: {
                        Label(workout.isPaused ? "继续" : "暂停", systemImage: workout.isPaused ? "play.fill" : "pause.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding()
                            .background(DS.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    }
                    Button { finishWorkout() } label: {
                        Label("结束", systemImage: "stop.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding()
                            .background(Color.red.opacity(0.8)).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    }
                }
            }
        }
    }

    private func startIfNeeded() {
        if task.status == .inProgress || task.status == .paused {
            workout.burnedCalories = task.burnedCalories
            workout.durationSeconds = task.durationSeconds
            workout.start(mode: task.taskMode)
            if task.status == .paused { workout.pause() }
        }
        refreshQuote()
    }

    private func startWorkout() {
        TaskStateMachine.transition(task, to: .inProgress)
        workout.start(mode: task.taskMode)
        refreshQuote()
    }

    private func updateTask() {
        let oldPercent = task.progressPercent
        task.updateProgress(burnedCalories: workout.burnedCalories, durationSeconds: workout.durationSeconds)
        if task.burnedCalories >= task.targetBurnCalories &&
           (task.status == .inProgress || task.status == .paused) {
            workout.stop()
            if task.status == .paused {
                TaskStateMachine.transition(task, to: .inProgress)
            }
            TaskStateMachine.transition(task, to: .completed)
            try? modelContext.save()
            onCompleted(task)
        }
        let newStage = MotivationalQuotes.stage(for: task.progressPercent)
        let oldStage = MotivationalQuotes.stage(for: oldPercent)
        if newStage != oldStage { refreshQuote() }
    }

    private func finishWorkout() {
        workout.stop()
        if task.burnedCalories >= task.targetBurnCalories {
            if task.status == .paused {
                TaskStateMachine.transition(task, to: .inProgress)
            }
            TaskStateMachine.transition(task, to: .completed)
        }
        try? modelContext.save()
        onCompleted(task)
    }

    private func refreshQuote() {
        let stage = MotivationalQuotes.stage(for: task.progressPercent)
        if let pick = MotivationalQuotes.randomQuote(for: stage, excluding: shownQuoteIndices) {
            shownQuoteIndices.insert(pick.index)
            withAnimation {
                quoteText = MotivationalQuotes.render(
                    template: pick.template, food: task.foodName,
                    progress: task.progressPercent, remaining: remaining
                )
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
