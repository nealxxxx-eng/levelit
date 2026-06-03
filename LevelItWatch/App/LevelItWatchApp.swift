import SwiftUI
import SwiftData
import LevelItShared

@main
struct LevelItWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(for: [
            DebtTask.self,
            Achievement.self,
            UserStats.self,
        ])
    }
}

/// 临时占位 — 第三轮实现 Watch UI 后替换
struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [DebtTask]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("磨平")
                    .font(.title2.bold())

                let pendingTasks = tasks.filter { $0.status.countsAsDebt }
                let pendingKcal = pendingTasks.reduce(0) { $0 + $1.estimatedCalories - $1.burnedCalories }

                Text("\(pendingKcal) kcal")
                    .font(.title.bold())
                    .foregroundStyle(.orange)

                Text("今日欠债")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
