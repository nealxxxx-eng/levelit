import SwiftUI
import SwiftData
import LevelItShared

struct TaskListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]
    @State private var filter: TaskFilter = .all
    @State private var taskToDelete: DebtTask?

    enum TaskFilter: String, CaseIterable {
        case all = "全部"
        case settled = "已结清"
        case active = "进行中"
        case expired = "已过期"

        func matches(_ task: DebtTask) -> Bool {
            switch self {
            case .all:     return true
            case .settled: return task.status == .settled || task.status == .completed
            case .active:  return task.isPendingForDay()
            case .expired: return task.status == .expired
            }
        }
    }

    private var filteredTasks: [DebtTask] {
        allTasks.filter { filter.matches($0) }
    }

    private var groupedTasks: [(String, [DebtTask])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTasks) { task -> String in
            if calendar.isDateInToday(task.createdAt) {
                return "今天"
            } else if calendar.isDateInYesterday(task.createdAt) {
                return "昨天"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MM月dd日"
                return formatter.string(from: task.createdAt)
            }
        }
        return grouped.sorted { $0.value.first?.createdAt ?? .distantPast > $1.value.first?.createdAt ?? .distantPast }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 筛选栏
            filterBar

            // 列表
            if filteredTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .navigationTitle("历史任务")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认删除", isPresented: .init(
            get: { taskToDelete != nil },
            set: { if !$0 { taskToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let task = taskToDelete {
                    deleteTask(task)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let task = taskToDelete {
                Text("删除「\(task.foodEmoji) \(task.foodName)」？此操作不可撤销。")
            }
        }
    }

    private func deleteTask(_ task: DebtTask) {
        // 同步到 Watch
        WCSyncService.shared.sendDeleteTask(taskId: task.id)
        // 清理食物照片
        if let fileName = task.foodImageFileName {
            FoodImageStore.delete(fileName: fileName)
        }
        // 从 SwiftData 删除
        modelContext.delete(task)
        try? modelContext.save()
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(TaskFilter.allCases, id: \.self) { f in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { filter = f }
                    } label: {
                        Text(f.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(filter == f ? DS.Colors.accent : DS.Colors.cardBackground)
                            .foregroundStyle(filter == f ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    // MARK: - Task List

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.lg) {
                ForEach(groupedTasks, id: \.0) { date, tasks in
                    Section {
                        ForEach(tasks) { task in
                            taskRow(task)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        taskToDelete = task
                                    } label: {
                                        Label("删除任务", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(date)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func taskRow(_ task: DebtTask) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Text(task.foodEmoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.foodName)
                    .font(.body.weight(.medium))
                HStack(spacing: DS.Spacing.xs) {
                    Text(task.status.displayName)
                        .font(.caption)
                    if task.progressPercent > 0 && task.status != .settled {
                        Text("· \(task.progressPercent)%")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(task.estimatedCalories) kcal")
                    .font(.subheadline)

                Text(task.taskMode.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            statusDot(task.status)
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .padding(.horizontal)
    }

    private func statusDot(_ status: TaskStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 10, height: 10)
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .settled, .completed: return .green
        case .inProgress:          return .blue
        case .paused:              return .yellow
        case .expired:             return .gray
        case .cancelled:           return .gray
        default:                   return .orange
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("还没有任务")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("拍一下食物开始你的第一单")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }
}
