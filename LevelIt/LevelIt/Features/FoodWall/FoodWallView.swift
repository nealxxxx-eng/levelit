import SwiftUI
import SwiftData
import LevelItShared

struct FoodWallView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealIntake.takenAt, order: .reverse) private var allIntakes: [MealIntake]
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]
    @State private var selectedTab = 0
    @State private var intakeToDelete: MealIntake?

    private var photoIntakes: [MealIntake] {
        allIntakes.filter { $0.foodImageFileName != nil }
    }

    private var settledIntakes: [MealIntake] {
        photoIntakes.filter { intake in
            linkedTask(for: intake)?.status == .settled
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("全部").tag(0)
                Text("已结清").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, DS.Spacing.sm)

            let intakes = selectedTab == 0 ? photoIntakes : settledIntakes

            if intakes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(intakes, id: \.id) { intake in
                            NavigationLink(value: AppRoute.foodDetail(intake)) {
                                PlateCell(intake: intake, task: linkedTask(for: intake))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    intakeToDelete = intake
                                } label: {
                                    Label("删除记录", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.lg)
                }
            }
        }
        .navigationTitle("美食墙")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认删除", isPresented: .init(
            get: { intakeToDelete != nil },
            set: { if !$0 { intakeToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let intake = intakeToDelete { deleteIntake(intake) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let intake = intakeToDelete {
                Text("删除「\(intake.foodEmoji) \(intake.foodName)」？照片会一并删除。")
            }
        }
    }

    private func linkedTask(for intake: MealIntake) -> DebtTask? {
        guard let taskId = intake.debtTaskId else { return nil }
        return allTasks.first { $0.id == taskId }
    }

    private func deleteIntake(_ intake: MealIntake) {
        if let task = linkedTask(for: intake), task.status.countsAsDebt {
            WCSyncService.shared.sendDeleteTask(taskId: task.id)
            if let fileName = task.foodImageFileName {
                FoodImageStore.delete(fileName: fileName)
            }
            modelContext.delete(task)
        }
        if let fileName = intake.foodImageFileName {
            FoodImageStore.delete(fileName: fileName)
        }
        modelContext.delete(intake)
        try? modelContext.save()
        WCSyncService.shared.pushTodayIntakeContext(modelContext: modelContext)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: selectedTab == 0 ? "fork.knife.circle" : "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(selectedTab == 0 ? "还没有拍过食物" : "还没有结清的任务")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(selectedTab == 0 ? "拍一张试试吧" : "完成运动后这里会出现战利品")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }
}

// MARK: - 餐盘单元格

struct PlateCell: View {
    let intake: MealIntake
    let task: DebtTask?
    @State private var foodImage: UIImage?
    @State private var imageLoaded = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(.systemGray5), Color(.systemGray6)],
                            center: .center,
                            startRadius: 50,
                            endRadius: 80
                        )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(.systemGray4), Color(.systemGray5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 8
                    )

                Circle()
                    .fill(Color(.systemGray6))
                    .padding(8)

                if let image = foodImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                        .padding(12)
                } else {
                    Text(intake.foodEmoji)
                        .font(.system(size: 40))
                }

                if task?.status == .settled {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                                .background(
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 22, height: 22)
                                )
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(intake.foodName)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Text("\(intake.estimatedCalories) kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .task {
            guard !imageLoaded, let fileName = intake.foodImageFileName else { return }
            imageLoaded = true
            let image = await Task.detached(priority: .utility) {
                FoodImageStore.load(fileName: fileName)
            }.value
            foodImage = image
        }
    }
}
