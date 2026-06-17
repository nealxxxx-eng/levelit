import SwiftUI
import SwiftData
import LevelItShared

/// App 生命周期统一协调器
///
/// 职责:
///   - 启动时: 一次性初始化 (WC configure, UserStats ensure, 通知注册)
///   - 回到前台时: 统一分发刷新任务 (同步/HK/过期检查)
///
/// 解决的问题:
///   - WCSyncService.configure() 从 HomeView.onAppear 上移到 App 启动
///   - scenePhase.active 从 HomeView 散乱处理上移到统一入口
///   - ensureStats() 的三件无关事情拆分到各自的 Owner
@Observable
final class AppLifecycleCoordinator {
    static let shared = AppLifecycleCoordinator()

    private var launched = false

    private init() {}

    // MARK: - App 启动 (一次性)

    @MainActor
    func appDidLaunch(container: ModelContainer) {
        guard !launched else { return }
        launched = true

        // 1. WC 同步服务配置 (尽早, 不依赖 View 出现)
        WCSyncService.shared.configure(modelContainer: container)

        // 2. 确保 UserStats 存在
        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<UserStats>())) ?? []
        if existing.isEmpty {
            context.insert(UserStats())
            try? context.save()
        }

        // 3. 首次过期检查
        TaskExpiryService.checkAndExpire(in: context)

        // 4. 首次全量同步
        WCSyncService.shared.performFullSync()
    }

    // MARK: - scenePhase.active (回到前台)

    @MainActor
    func handleBecameActive(container: ModelContainer) {
        // WC 同步已由 WCSyncService.handleEnterForeground() 处理

        // 1. HealthKit 缓存失效, 下次访问时会重新查询
        HealthKitDataStore.shared.invalidateCache()

        // 2. 任务过期检查
        let context = container.mainContext
        TaskExpiryService.checkAndExpire(in: context)

        // 3. PK 进度刷新：把 Apple Watch 等外部运动（仅进 HealthKit、不经磨平
        //    运动事件）计入进行中的挑战。否则用户必须手动进「朋友 PK」页下拉刷新。
        //    放在 invalidateCache 之后，refreshAll 内部会 force 重新查询 HealthKit。
        Task { await PKChallengeProgressService.refreshAll(in: context) }
    }
}
