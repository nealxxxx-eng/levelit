import SwiftUI
import SwiftData
import LevelItShared

struct FoodDetailView: View {
    let intake: MealIntake
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]
    @State private var foodImage: UIImage?

    private var task: DebtTask? {
        guard let taskId = intake.debtTaskId else { return nil }
        return allTasks.first { $0.id == taskId }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                largePlate
                foodInfo

                if let task, task.durationSeconds > 0 || task.burnedCalories > 0 {
                    workoutDetail(task)
                }

                statusSection
            }
            .padding()
        }
        .navigationTitle(intake.foodName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadImage() }
    }

    private var largePlate: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(.systemGray5), Color(.systemGray6)],
                        center: .center,
                        startRadius: 80,
                        endRadius: 140
                    )
                )
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(.systemGray4), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 12
                )

            Circle()
                .fill(Color(.systemGray6))
                .padding(12)

            if let image = foodImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .padding(18)
            } else {
                Text(intake.foodEmoji)
                    .font(.system(size: 80))
            }
        }
        .frame(width: 260, height: 260)
        .padding(.top, DS.Spacing.md)
    }

    private var foodInfo: some View {
        let level = TaskLevel.from(calories: intake.estimatedCalories)

        return VStack(spacing: DS.Spacing.sm) {
            Text(intake.foodEmoji)
                .font(.title)
            Text(intake.foodName)
                .font(.title2.weight(.bold))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(intake.estimatedCalories)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(level.color)
                Text("kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: DS.Spacing.sm) {
                Text(level.displayName)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(level.color.opacity(0.2))
                    .foregroundStyle(level.color)
                    .clipShape(Capsule())

                Text("\(intake.mealKind.emoji) \(intake.mealKind.displayName)")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DS.Colors.accent.opacity(0.12))
                    .foregroundStyle(DS.Colors.accent)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func workoutDetail(_ task: DebtTask) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Label("运动记录", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(DS.Colors.accent)

            HStack(spacing: 0) {
                detailItem(
                    value: "\(task.burnedCalories)",
                    unit: "kcal",
                    label: "已消耗"
                )
                Divider().frame(height: 40)
                detailItem(
                    value: formatDuration(task.durationSeconds),
                    unit: "",
                    label: "运动时长"
                )
                Divider().frame(height: 40)
                detailItem(
                    value: "\(task.progressPercent)",
                    unit: "%",
                    label: "完成度"
                )
            }

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: task.taskMode.iconName)
                    .foregroundStyle(DS.Colors.accent)
                Text(task.taskMode.displayName)
                    .font(.subheadline)
                if task.isOverAchieved {
                    Text("超额完成!")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Colors.accent.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor(for: task))
                        .frame(width: geo.size.width * min(1.0, Double(task.progressPercent) / 100.0))
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func progressColor(for task: DebtTask) -> Color {
        if task.progressPercent >= 100 { return .green }
        if task.progressPercent >= 50 { return DS.Colors.accent }
        return .orange
    }

    private func detailItem(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusSection: some View {
        HStack(spacing: DS.Spacing.md) {
            Label(statusText, systemImage: statusIcon)
                .font(.subheadline)
                .foregroundStyle(statusColor)

            Spacer()

            Text(intake.takenAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var statusText: String {
        if let task {
            return task.status.displayName
        }
        return intake.verdictKind.displayName
    }

    private var statusIcon: String {
        guard let task else { return "checkmark.circle" }
        switch task.status {
        case .settled: return "checkmark.seal.fill"
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "figure.run"
        case .paused: return "pause.circle.fill"
        default: return "clock"
        }
    }

    private var statusColor: Color {
        guard let task else {
            return intake.verdictKind == .over || intake.verdictKind == .snack ? .orange : .green
        }
        switch task.status {
        case .settled: return .green
        case .completed: return .blue
        case .inProgress: return DS.Colors.accent
        case .paused: return .yellow
        default: return .secondary
        }
    }

    private func loadImage() async {
        guard let fileName = intake.foodImageFileName else { return }
        let image = await Task.detached(priority: .utility) {
            FoodImageStore.load(fileName: fileName)
        }.value
        foodImage = image
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 { return "\(m):\(String(format: "%02d", s))" }
        return "\(s)s"
    }
}
