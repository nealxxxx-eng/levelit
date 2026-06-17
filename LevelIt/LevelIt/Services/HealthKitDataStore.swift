import Foundation
import HealthKit
import Observation

/// 集中管理 HealthKit 运动数据的缓存和生命周期
///
/// 职责:
///   - 授权: 只请求一次，缓存授权结果
///   - 今日外部运动: 带日期感知的 TTL 缓存 (60s)
///   - 周/月统计运动: 按 period key 缓存
///   - 失效: scenePhase.active 时由 AppLifecycleCoordinator 调用 invalidateCache()
///
/// 消费方:
///   - HomeView: todayExternalWorkouts (banner)
///   - HomeView/TodayView: todayWorkoutSummaries (今日运动展示)
///   - StatsView: periodWorkouts (图表)
///   - WorkoutImportView: todayExternalWorkouts (导入列表)
@Observable
final class HealthKitDataStore {
    static let shared = HealthKitDataStore()

    // MARK: - 公开数据

    private(set) var todayExternalWorkouts: [HealthKitImportService.ImportableWorkout] = []
    private(set) var todayWorkoutSummaries: [HealthKitImportService.WorkoutSummary] = []
    private(set) var periodWorkouts: [HealthKitImportService.WorkoutSummary] = []
    private(set) var isLoadingToday = false
    private(set) var isLoadingPeriod = false

    // MARK: - 缓存状态

    private var lastTodayFetchDate: Date?
    private var lastTodaySummaryFetchDate: Date?
    private var lastPeriodKey: String?
    private var authorizationRequested = false
    private static let todayTTL: TimeInterval = 60

    private init() {}

    // MARK: - 授权 (只弹一次)

    func ensureAuthorization() async -> Bool {
        guard HealthKitImportService.isAvailable else { return false }
        if authorizationRequested { return true }
        let result = await HealthKitImportService.requestAuthorization()
        if result { authorizationRequested = true }
        return result
    }

    // MARK: - 今日外部运动 (HomeView banner + WorkoutImportView)

    /// 刷新今日外部运动，带日期感知 + 60 秒 TTL
    @MainActor
    func refreshTodayWorkouts(force: Bool = false) async {
        guard HealthKitImportService.isAvailable else { return }

        let now = Date()
        if !force, let last = lastTodayFetchDate,
           Calendar.current.isDate(last, inSameDayAs: now),
           now.timeIntervalSince(last) < Self.todayTTL {
            return
        }

        isLoadingToday = true
        let workouts = await HealthKitImportService.fetchTodayExternalWorkouts()
        todayExternalWorkouts = workouts
        lastTodayFetchDate = now
        isLoadingToday = false
    }

    /// 刷新今日所有运动摘要（含 LevelIt 自己记录的运动），用于首页和今日页展示。
    @MainActor
    func refreshTodayWorkoutSummaries(force: Bool = false) async {
        guard HealthKitImportService.isAvailable else { return }

        let now = Date()
        if !force, let last = lastTodaySummaryFetchDate,
           Calendar.current.isDate(last, inSameDayAs: now),
           now.timeIntervalSince(last) < Self.todayTTL {
            return
        }

        isLoadingToday = true
        _ = await ensureAuthorization()
        let start = Calendar.current.startOfDay(for: now)
        todayWorkoutSummaries = await HealthKitImportService.fetchWorkoutsInRange(start: start, end: now)
        lastTodaySummaryFetchDate = now
        isLoadingToday = false
    }

    // MARK: - 周/月统计运动 (StatsView)

    /// 刷新指定时间段的运动数据，按 period key 缓存避免重复查询
    @MainActor
    func refreshPeriodWorkouts(start: Date, end: Date, force: Bool = false) async {
        let key = "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
        if !force, key == lastPeriodKey, !periodWorkouts.isEmpty {
            return
        }

        isLoadingPeriod = true
        _ = await ensureAuthorization()
        let workouts = await HealthKitImportService.fetchWorkoutsInRange(start: start, end: end)
        periodWorkouts = workouts
        lastPeriodKey = key
        isLoadingPeriod = false
    }

    // MARK: - 缓存失效 (scenePhase.active 时调用)

    @MainActor
    func invalidateCache() {
        lastTodayFetchDate = nil
        lastTodaySummaryFetchDate = nil
        lastPeriodKey = nil
    }
}
