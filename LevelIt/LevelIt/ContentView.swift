import SwiftUI
import SwiftData
import LevelItShared

/// 根视图 — 注册门控 + NavigationStack + 路由分发
struct ContentView: View {
    @State private var navigationPath = NavigationPath()
    @State private var isAuthenticated = AuthSessionStore.isAuthenticated
    @State private var isRestoringAccount = false

    var body: some View {
        Group {
            if isRestoringAccount {
                accountRestoreView
            } else if !isAuthenticated {
                AuthGateView {
                    withAnimation { isAuthenticated = true }
                }
            } else {
                mainApp
            }
        }
        .task {
            guard isAuthenticated else { return }
            await restoreFromAliyun()
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

    // MARK: - 阿里云账号恢复

    private var accountRestoreView: some View {
        VStack(spacing: DS.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.3)
            Text("正在恢复账户数据...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func restoreFromAliyun() async {
        isRestoringAccount = true
        defer { isRestoringAccount = false }

        do {
            let profile = try await AliyunAuthService.fetchCurrentUser()
            UserProfileStore.save(profile)
        } catch AliyunAuthService.AuthError.missingSession {
            // Token 不存在或已损坏，必须重新登录
            await MainActor.run {
                AliyunAuthService.logout()
                withAnimation { isAuthenticated = false }
            }
        } catch AliyunAuthService.AuthError.serverError(let message) where message.hasPrefix("HTTP 401") {
            // 服务器明确拒绝 token（过期/无效），必须重新登录
            await MainActor.run {
                AliyunAuthService.logout()
                withAnimation { isAuthenticated = false }
            }
        } catch {
            // 网络错误、超时、服务器临时不可用 — 保持登录状态，静默忽略
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

        case .pkChallengeCenter:
            PKChallengeCenterView()

        case .stats:
            StatsView()

        case .today:
            TodayView()

        case .settings:
            SettingsView {
                if !navigationPath.isEmpty {
                    navigationPath.removeLast()
                }
            } onLogout: {
                navigationPath = NavigationPath()
                withAnimation { isAuthenticated = false }
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
        .modelContainer(for: [DebtTask.self, Achievement.self, UserStats.self, PKChallenge.self], inMemory: true)
}
