import SwiftUI
import SwiftData
import LevelItShared

@main
struct LevelItApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: DebtTask.self,
                Achievement.self,
                UserStats.self,
                AnomalyLog.self,
                MealIntake.self,
                ImportedWorkoutRecord.self,
                DailyCalorieBalance.self
            )
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await NotificationScheduler.requestAndSchedule()
                    await MainActor.run {
                        AppLifecycleCoordinator.shared.appDidLaunch(container: container)
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                WCSyncService.shared.handleEnterForeground()
                AppLifecycleCoordinator.shared.handleBecameActive(container: container)
            case .background:
                WCSyncService.shared.handleEnterBackground()
            default:
                break
            }
        }
    }
}
