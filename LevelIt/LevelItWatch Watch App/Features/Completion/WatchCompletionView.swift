import SwiftUI
import SwiftData
import WatchKit
import LevelItShared

struct WatchCompletionView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: DebtTask
    var onDone: () -> Void

    @State private var processed = false
    @State private var newBadge: AchievementType?

    private var isFullyComplete: Bool {
        task.burnedCalories >= task.targetBurnCalories ||
        task.progressPercent >= 100 ||
        task.status == .completed ||
        task.status == .settled
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if isFullyComplete {
                    if task.isOverAchieved {
                        Text("🏆").font(.largeTitle)
                        Text("超额完成!").font(.headline).foregroundStyle(.orange)
                        Text("\(task.progressPercent)%").font(.title2.weight(.bold))
                    } else {
                        Text("✅").font(.largeTitle)
                        Text("已结清").font(.headline)
                    }
                } else {
                    Text("⏸️").font(.largeTitle)
                    Text("已磨平 \(task.progressPercent)%").font(.headline)
                    Text("下次继续!").font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    HStack {
                        Text("消耗").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(task.burnedCalories) kcal").font(.caption.weight(.medium))
                    }
                    HStack {
                        Text("用时").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDuration(task.durationSeconds)).font(.caption.weight(.medium))
                    }
                }
                .padding(.vertical, 4)

                if let badge = newBadge {
                    VStack(spacing: 4) {
                        Image(systemName: badge.iconName).font(.title2).foregroundStyle(.yellow)
                        Text(badge.rawValue).font(.caption.weight(.bold))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.yellow.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    onDone()
                } label: {
                    Text("完成").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isFullyComplete ? .green : .orange)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { processResult() }
    }

    private func processResult() {
        guard !processed else { return }
        processed = true

        if isFullyComplete {
            if task.status == .completed || task.status == .inProgress {
                if task.status == .inProgress {
                    TaskStateMachine.transition(task, to: .completed)
                }
                TaskStateMachine.transition(task, to: .settled)
            }

            if let stats = try? modelContext.fetch(FetchDescriptor<UserStats>()).first {
                let oldStreak = stats.currentStreak()
                stats.recordCompletion(burnedCalories: task.burnedCalories)
                let newStreak = stats.currentStreak()
                let oldBadge = AchievementType.highestAchievable(forStreak: oldStreak)
                let newBadgeType = AchievementType.highestAchievable(forStreak: newStreak)
                if let badge = newBadgeType, badge != oldBadge {
                    modelContext.insert(Achievement(type: badge, streakDays: newStreak))
                    newBadge = badge
                }
            }
            WatchHapticManager.play(for: 100)
        } else {
            if task.status == .inProgress {
                TaskStateMachine.transition(task, to: .paused)
            }
        }

        try? modelContext.save()
        WatchSyncReceiver.shared.sendStatusUpdate(taskId: task.id, status: task.status, task: task)
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d分%02d秒", seconds / 60, seconds % 60)
    }
}
