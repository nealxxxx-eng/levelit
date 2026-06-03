import SwiftUI
import SwiftData
import LevelItShared

/// 根视图 — 注册门控 + NavigationStack + 路由分发
struct ContentView: View {
    @State private var navigationPath = NavigationPath()
    @State private var isRegistered = UserProfileStore.isRegistered
    @State private var isRestoringFromCloud = false

    var body: some View {
        Group {
            if isRestoringFromCloud {
                cloudRestoreView
            } else if !isRegistered {
                OnboardingProfileView {
                    withAnimation { isRegistered = true }
                }
            } else {
                mainApp
            }
        }
        .task {
            // 首次启动尝试从 CloudKit 恢复
            guard !isRegistered else { return }
            await tryRestoreFromCloud()
        }
    }

    // MARK: - 主应用

    private var mainApp: some View {
        NavigationStack(path: $navigationPath) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    routeView(for: route)
                }
        }
        .environment(\.popToRoot) {
            navigationPath = NavigationPath()
        }
    }

    // MARK: - CloudKit 恢复中

    private var cloudRestoreView: some View {
        VStack(spacing: DS.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.3)
            Text("正在恢复账户数据...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func tryRestoreFromCloud() async {
        isRestoringFromCloud = true
        defer { isRestoringFromCloud = false }

        guard await CloudKitService.checkAccountStatus() else { return }

        do {
            if let profile = try await CloudKitService.fetch() {
                UserProfileStore.save(profile)
                await MainActor.run {
                    withAnimation { isRegistered = true }
                }
            }
        } catch {
            // 恢复失败不阻塞，让用户走注册流程
            print("CloudKit restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 路由

    @ViewBuilder
    private func routeView(for route: AppRoute) -> some View {
        switch route {
        case .scan:
            ScanView { result in
                navigationPath.append(AppRoute.analysis(result))
            }

        case .manualSelect:
            ManualSelectView { result in
                navigationPath.append(AppRoute.analysis(result))
            }

        case .analysis(let result):
            AnalysisView(result: result) { route in
                navigationPath.append(route)
            }

        case .mealOverConfirm(let result, let mealKind, let actualKcal, let gapKcal, let accumulatedBefore, let intakeId):
            MealOverConfirmView(
                originalResult: result,
                mealKind: mealKind,
                actualKcal: actualKcal,
                gapKcal: gapKcal,
                accumulatedBefore: accumulatedBefore,
                intakeId: intakeId
            ) { adjusted, forwardedIntakeId in
                navigationPath.append(AppRoute.taskMode(result: adjusted, intakeId: forwardedIntakeId))
            }

        case .taskMode(let result, let intakeId):
            TaskModeView(analysisResult: result, intakeId: intakeId) { task in
                navigationPath.append(AppRoute.taskCreated(task))
            }

        case .taskCreated(let task):
            TaskCreatedView(task: task)

        case .taskDetail(let task):
            TaskDetailView(task: task) { completedTask in
                navigationPath.append(AppRoute.result(completedTask))
            }

        case .progress(let task):
            TaskProgressView(task: task) { completedTask in
                navigationPath.append(AppRoute.result(completedTask))
            }

        case .result(let task):
            ResultView(task: task)

        case .share(let task):
            ShareCardView(task: task)

        case .taskList:
            TaskListView()

        case .foodWall:
            FoodWallView()

        case .foodDetail(let intake):
            FoodDetailView(intake: intake)

        case .workoutImport:
            WorkoutImportView()

        case .stats:
            StatsView()

        case .today:
            TodayView()

        case .settings:
            SettingsView {
                if !navigationPath.isEmpty {
                    navigationPath.removeLast()
                }
            }

        case .mealQuotaConfig:
            MealQuotaConfigView {
                if !navigationPath.isEmpty {
                    navigationPath.removeLast()
                }
            }

        case .mealIntakeEdit(let intake):
            MealIntakeEditView(intake: intake)

        case .anomalyLogForm(let date):
            AnomalyLogFormView(date: date)

        case .anomalyLogList:
            AnomalyLogListView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [DebtTask.self, Achievement.self, UserStats.self], inMemory: true)
}
