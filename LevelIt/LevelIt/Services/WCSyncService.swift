import Foundation
import WatchConnectivity
import SwiftData
import LevelItShared

/// iPhone 端 WatchConnectivity 同步服务
///
/// 职责分层:
///   - 传输层: send / transferUserInfo / sendMessage
///   - 接收层: 处理 Watch 发来的消息
///   - 同步决策: performFullSync (唯一全量同步入口, 含对账)
final class WCSyncService: NSObject {
    static let shared = WCSyncService()

    private var session: WCSession?
    private var modelContainer: ModelContainer?
    private var configured = false
    private(set) var isActivated = false

    /// App 是否在前台 (后台时缓存消息, 回前台统一处理)
    /// 仅从主线程读写
    @MainActor var isInForeground = true

    /// 待发送队列 (session 未就绪时暂存)
    private var pendingMessages: [[String: Any]] = []
    private let pendingLock = NSLock()

    /// 后台收到的消息缓冲区 (回前台时统一处理)
    private var backgroundBuffer: [[String: Any]] = []
    private let bufferLock = NSLock()

    /// 时间戳去重 (上限 200 条, 超出时清理已终止任务)
    private var lastProcessedTimestamp: [String: TimeInterval] = [:]
    private static let maxDedupEntries = 200

    /// 全量同步节流 (10 秒内不重复)
    private var lastFullSyncTime: Date?
    private static let fullSyncThrottle: TimeInterval = 10

    private override init() {
        super.init()
    }

    func configure(modelContainer: ModelContainer) {
        guard !configured else { return }
        configured = true
        self.modelContainer = modelContainer
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - 前台/后台切换

    /// App 回到前台时调用: 处理缓冲消息 + 全量同步
    @MainActor
    func handleEnterForeground() {
        isInForeground = true
        // 线程安全地取出后台缓冲
        let buffered: [[String: Any]]
        bufferLock.lock()
        buffered = backgroundBuffer
        backgroundBuffer.removeAll()
        bufferLock.unlock()

        if !buffered.isEmpty {
            Task { @MainActor in
                for message in buffered {
                    routeMessage(message)
                    await Task.yield()
                }
            }
        }
        performFullSync()
    }

    @MainActor
    func handleEnterBackground() {
        isInForeground = false
    }

    /// 统一消息路由
    @MainActor
    private func routeMessage(_ message: [String: Any]) {
        let type = message["_wcType"] as? String
        switch type {
        case AppConstants.WCMessageType.taskSync: handleTaskSync(message)
        case AppConstants.WCMessageType.taskDelete: handleTaskDelete(message)
        case AppConstants.WCMessageType.progressUpdate: handleProgressUpdate(message)
        case AppConstants.WCMessageType.requestSync: performFullSync(force: true)
        default: break
        }
    }

    /// 后台时缓存消息, 前台时直接处理
    /// 注意: 从 WCSession delegate 回调 (后台线程) 调用
    private func bufferOrProcess(_ message: [String: Any]) {
        Task { @MainActor in
            if self.isInForeground {
                self.routeMessage(message)
            } else {
                self.bufferLock.lock()
                self.backgroundBuffer.append(message)
                self.bufferLock.unlock()
            }
        }
    }

    // MARK: - 发送 (传输层)

    func sendTask(_ task: DebtTask) {
        sendTaskSnapshot(task)
    }

    /// 发送任务完整快照 (不做状态转换, 用于导入/结清等已有任务的同步)
    func sendTaskSnapshot(_ task: DebtTask) {
        var payload = task.toDict()
        payload["_wcType"] = AppConstants.WCMessageType.taskSync
        payload["_wcTimestamp"] = Date().timeIntervalSince1970
        send(payload)
    }

    func sendDeleteTask(taskId: String) {
        let payload: [String: Any] = [
            "_wcType": AppConstants.WCMessageType.taskDelete,
            "_wcTimestamp": Date().timeIntervalSince1970,
            "id": taskId,
        ]
        send(payload)
    }

    /// 把"今日摄入总数"写到 applicationContext，Watch 端立即可见。
    /// 调用时机：MealIntake 写入 / 编辑 / 删除后；performFullSync 时。
    @MainActor
    func pushTodayIntakeContext(modelContext: ModelContext) {
        guard let session, isActivated else { return }
        let intakes = (try? modelContext.fetch(FetchDescriptor<MealIntake>())) ?? []
        let kcal = MealIntakeAggregator.dailyTotalKcal(from: intakes, on: Date())
        let cal = Calendar.current
        let count = intakes.filter { cal.isDateInToday($0.takenAt) }.count
        let payload: [String: Any] = [
            "_wcType": AppConstants.WCMessageType.intakeSummary,
            "_wcTimestamp": Date().timeIntervalSince1970,
            AppConstants.WCPayloadKey.todayIntakeKcal: kcal,
            AppConstants.WCPayloadKey.todayIntakeCount: count,
        ]
        try? session.updateApplicationContext(payload)
    }

    func sendStatusUpdate(taskId: String, status: TaskStatus) {
        let payload: [String: Any] = [
            "_wcType": AppConstants.WCMessageType.taskSync,
            "_wcTimestamp": Date().timeIntervalSince1970,
            "id": taskId,
            "status": status.rawValue,
            "_statusOnly": true,
        ]
        send(payload)
    }

    private func send(_ payload: [String: Any]) {
        guard let session else {
            pendingLock.lock()
            pendingMessages.append(payload)
            pendingLock.unlock()
            return
        }
        guard isActivated else {
            pendingLock.lock()
            pendingMessages.append(payload)
            pendingLock.unlock()
            return
        }
        session.transferUserInfo(payload)
    }

    private func flushPendingMessages() {
        pendingLock.lock()
        let messages = pendingMessages
        pendingMessages.removeAll()
        pendingLock.unlock()
        for msg in messages {
            send(msg)
        }
    }

    // MARK: - 全量同步 (唯一入口, 含对账)

    /// 全量同步: 推送所有任务快照 + 对账清单
    /// 这是触发全量同步的唯一入口, 内置 10 秒节流
    @MainActor
    func performFullSync(force: Bool = false) {
        guard isActivated else { return }
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        guard let container = modelContainer else { return }

        // 节流: 10 秒内不重复 (force 可绕过)
        let now = Date()
        if !force, let last = lastFullSyncTime, now.timeIntervalSince(last) < Self.fullSyncThrottle {
            return
        }
        lastFullSyncTime = now

        let context = container.mainContext
        let allTasks = (try? context.fetch(FetchDescriptor<DebtTask>())) ?? []

        // 1. 推送所有任务 (含终态, 确保结清/过期状态同步到 Watch)
        for task in allTasks {
            sendTaskSnapshot(task)
        }

        // 2. 对账清单包含全量 ID (Watch 据此检测孤儿, 含终态)
        let allIds = allTasks.map { $0.id }
        let reconcilePayload: [String: Any] = [
            "_wcType": AppConstants.WCMessageType.reconcile,
            "_wcTimestamp": now.timeIntervalSince1970,
            "activeTaskIds": allIds,
        ]
        send(reconcilePayload)

        // 3. 顺带刷新今日摄入摘要
        pushTodayIntakeContext(modelContext: context)
    }

    // MARK: - 去重

    private func shouldProcess(taskId: String, timestamp: TimeInterval) -> Bool {
        if let last = lastProcessedTimestamp[taskId], timestamp <= last {
            return false
        }
        lastProcessedTimestamp[taskId] = timestamp
        // 超过上限时淘汰最旧的条目
        if lastProcessedTimestamp.count > Self.maxDedupEntries {
            let sorted = lastProcessedTimestamp.sorted { $0.value < $1.value }
            let dropCount = lastProcessedTimestamp.count - Self.maxDedupEntries / 2
            for (key, _) in sorted.prefix(dropCount) {
                lastProcessedTimestamp.removeValue(forKey: key)
            }
        }
        return true
    }

    // MARK: - 自动完成检查

    /// 同步更新 burnedCalories 后, 检查是否应该自动结清
    private func autoCompleteIfNeeded(_ task: DebtTask) {
        guard task.burnedCalories >= task.targetBurnCalories else { return }
        guard task.status == .created || task.status == .synced || task.status == .inProgress || task.status == .paused else { return }
        // created/synced/paused → completed 不合法, 需先进入 inProgress
        if task.status != .inProgress {
            TaskStateMachine.transition(task, to: .inProgress)
        }
        TaskStateMachine.transition(task, to: .completed)
        TaskStateMachine.transition(task, to: .settled)
    }

    private func mergeDefinitionFields(into task: DebtTask, from message: [String: Any]) {
        guard task.status == .created || task.status == .synced else { return }
        if let foodName = message["foodName"] as? String { task.foodName = foodName }
        if let foodEmoji = message["foodEmoji"] as? String { task.foodEmoji = foodEmoji }
        if let calories = message["estimatedCalories"] as? Int {
            task.estimatedCalories = CalorieCalculator.clampedCalories(calories)
            task.taskLevel = TaskLevel.from(calories: task.estimatedCalories)
        }
        if let target = message["targetBurnCalories"] as? Int {
            task.targetBurnCalories = CalorieCalculator.clampedCalories(target)
        }
        if let minutes = message["estimatedMinutes"] as? Int { task.estimatedMinutes = max(1, minutes) }
        if let modeRaw = message["taskMode"] as? String,
           let mode = TaskMode(rawValue: modeRaw) {
            task.taskMode = mode
        }
        if let levelRaw = message["taskLevel"] as? String,
           let level = TaskLevel(rawValue: levelRaw) {
            task.taskLevel = level
        }
        if let fileName = message["foodImageFileName"] as? String {
            task.foodImageFileName = fileName
        }
    }

    // MARK: - 处理接收

    @MainActor
    private func handleProgressUpdate(_ message: [String: Any]) {
        guard
            let taskId = message["taskId"] as? String,
            let burned = message["burned"] as? Int,
            let percent = message["percent"] as? Int,
            let duration = message["duration"] as? Int,
            let timestamp = message["_wcTimestamp"] as? TimeInterval
        else { return }

        guard shouldProcess(taskId: taskId, timestamp: timestamp) else { return }
        guard let container = modelContainer else { return }

        let context = container.mainContext
        let allTasks = (try? context.fetch(FetchDescriptor<DebtTask>())) ?? []
        guard let task = allTasks.first(where: { $0.id == taskId }) else { return }

        task.burnedCalories = max(task.burnedCalories, burned)
        task.progressPercent = max(task.progressPercent, percent)
        task.durationSeconds = max(task.durationSeconds, duration)
        task.lastSyncAt = Date()
        autoCompleteIfNeeded(task)
        try? context.save()
        Task { @MainActor in
            await PKChallengeProgressService.refreshForTask(taskId: taskId, in: context)
        }
    }

    @MainActor
    private func handleTaskSync(_ message: [String: Any]) {
        guard
            let taskId = message["id"] as? String,
            let timestamp = message["_wcTimestamp"] as? TimeInterval
        else { return }

        guard shouldProcess(taskId: taskId, timestamp: timestamp) else { return }
        guard let container = modelContainer else { return }

        let context = container.mainContext
        let allTasks = (try? context.fetch(FetchDescriptor<DebtTask>())) ?? []

        if let statusOnly = message["_statusOnly"] as? Bool, statusOnly,
           let statusRaw = message["status"] as? String,
           let status = TaskStatus(rawValue: statusRaw) {
            if let existing = allTasks.first(where: { $0.id == taskId }) {
                if let b = message["burnedCalories"] as? Int { existing.burnedCalories = max(existing.burnedCalories, b) }
                if let p = message["progressPercent"] as? Int { existing.progressPercent = max(existing.progressPercent, p) }
                if let d = message["durationSeconds"] as? Int { existing.durationSeconds = max(existing.durationSeconds, d) }
                if status == .completed || status == .settled {
                    autoCompleteIfNeeded(existing)
                } else {
                    TaskStateMachine.transition(existing, to: status)
                }
                if let ts = message["completedAt"] as? TimeInterval { existing.completedAt = Date(timeIntervalSince1970: ts) }
                if status == .settled && existing.completedAt == nil {
                    existing.completedAt = Date()
                }
                try? context.save()
                Task { @MainActor in
                    await PKChallengeProgressService.refreshForTask(taskId: taskId, in: context)
                }
            }
            return
        }

        if let existing = allTasks.first(where: { $0.id == taskId }) {
            mergeDefinitionFields(into: existing, from: message)
            existing.burnedCalories = max(existing.burnedCalories, message["burnedCalories"] as? Int ?? 0)
            existing.progressPercent = max(existing.progressPercent, message["progressPercent"] as? Int ?? 0)
            existing.durationSeconds = max(existing.durationSeconds, message["durationSeconds"] as? Int ?? 0)
            existing.isOverAchieved = message["isOverAchieved"] as? Bool ?? existing.isOverAchieved
            if let statusRaw = message["status"] as? String,
               let status = TaskStatus(rawValue: statusRaw) {
                if status == .completed || status == .settled {
                    autoCompleteIfNeeded(existing)
                } else {
                    TaskStateMachine.transition(existing, to: status)
                }
            }
            if let ts = message["completedAt"] as? TimeInterval { existing.completedAt = Date(timeIntervalSince1970: ts) }
            if existing.status == .settled && existing.completedAt == nil {
                existing.completedAt = Date()
            }
            existing.lastSyncAt = Date()
            autoCompleteIfNeeded(existing)
            try? context.save()
            Task { @MainActor in
                await PKChallengeProgressService.refreshForTask(taskId: taskId, in: context)
            }
            return
        } else {
            if let newTask = DebtTask.fromDict(message) {
                context.insert(newTask)
            }
        }
        try? context.save()
    }

    @MainActor
    private func handleTaskDelete(_ message: [String: Any]) {
        guard let taskId = message["id"] as? String else { return }
        guard let container = modelContainer else { return }

        let context = container.mainContext
        let allTasks = (try? context.fetch(FetchDescriptor<DebtTask>())) ?? []
        if let task = allTasks.first(where: { $0.id == taskId }) {
            if let fileName = task.foodImageFileName {
                FoodImageStore.delete(fileName: fileName)
            }
            context.delete(task)
            try? context.save()
        }
    }
}

// MARK: - WCSessionDelegate

extension WCSyncService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            isActivated = true
            flushPendingMessages()
            Task { @MainActor in performFullSync() }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        isActivated = false
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        if session.isPaired && session.isWatchAppInstalled && isActivated {
            Task { @MainActor in
                guard self.isInForeground else { return }
                self.performFullSync()
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        bufferOrProcess(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        bufferOrProcess(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        bufferOrProcess(message)
    }
}
