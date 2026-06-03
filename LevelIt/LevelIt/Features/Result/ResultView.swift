import SwiftUI
import SwiftData
import LevelItShared

struct ResultView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.popToRoot) private var popToRoot
    @Bindable var task: DebtTask
    @State private var animationDone = false
    @State private var newBadge: AchievementType?

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            if task.status == .completed && !animationDone {
                // 结清动画
                SettledAnimationView(
                    foodEmoji: task.foodEmoji,
                    foodName: task.foodName
                ) {
                    settleTask()
                    animationDone = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 结果详情
                resultContent
            }
        }
        .navigationTitle("结果")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!animationDone && task.status == .completed)
    }

    // MARK: - Result Content

    private var resultContent: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                // 状态标题
                statusHeader

                // 统计
                statsCard

                // 新徽章
                if let badge = newBadge {
                    badgeCard(badge)
                }

                // 操作按钮
                VStack(spacing: DS.Spacing.md) {
                    NavigationLink(value: AppRoute.share(task)) {
                        Label("生成分享卡", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DS.Colors.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    }

                    Button {
                        popToRoot()
                    } label: {
                        Label("返回首页", systemImage: "house.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DS.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    }
                }
            }
            .padding()
        }
    }

    private var statusHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            if task.isOverAchieved {
                Text("🏆")
                    .font(.system(size: 60))
                Text("超额完成!")
                    .font(.title.weight(.bold))
                    .foregroundStyle(DS.Colors.accent)
                Text("还多了 \(task.progressPercent - 100)%，下次可以白嗝一口")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if task.status == .settled || task.status == .completed {
                Text("✅")
                    .font(.system(size: 60))
                Text("已结清")
                    .font(.title.weight(.bold))
            } else {
                Text("已磨平 \(task.progressPercent)%")
                    .font(.title.weight(.bold))
                Text("下次继续!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.xl)
    }

    private var statsCard: some View {
        VStack(spacing: DS.Spacing.md) {
            statRow(label: "食物", value: "\(task.foodEmoji) \(task.foodName)")
            Divider()
            statRow(label: "目标", value: "\(task.targetBurnCalories) kcal")
            Divider()
            statRow(label: "已消耗", value: "\(task.burnedCalories) kcal")
            Divider()
            statRow(label: "完成度", value: "\(task.progressPercent)%")
            Divider()
            statRow(label: "用时", value: formatDuration(task.durationSeconds))
            Divider()
            statRow(label: "模式", value: task.taskMode.displayName)
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func badgeCard(_ badge: AchievementType) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: badge.iconName)
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
                .symbolEffect(.pulse)

            Text("新徽章解锁!")
                .font(.headline)

            Text(badge.rawValue)
                .font(.title3.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            LinearGradient(
                colors: [.yellow.opacity(0.1), .orange.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Logic

    private func settleTask() {
        TaskStateMachine.transition(task, to: .settled)

        // 更新统计
        if let stats = try? modelContext.fetch(FetchDescriptor<UserStats>()).first {
            let oldStreak = stats.currentStreak()
            stats.recordCompletion(burnedCalories: task.burnedCalories)
            let newStreak = stats.currentStreak()

            // 检查新徽章
            let oldBadge = AchievementType.highestAchievable(forStreak: oldStreak)
            let newBadgeType = AchievementType.highestAchievable(forStreak: newStreak)

            if let badge = newBadgeType, badge != oldBadge {
                let achievement = Achievement(type: badge, streakDays: newStreak)
                modelContext.insert(achievement)
                newBadge = badge
            }
        }

        // 显式保存 + 发完整快照到 Watch
        try? modelContext.save()
        WCSyncService.shared.sendTaskSnapshot(task)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d 分 %02d 秒", m, s)
    }
}
