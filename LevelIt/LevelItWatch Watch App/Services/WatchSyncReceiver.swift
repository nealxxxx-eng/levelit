import Foundation
import WatchConnectivity
import SwiftData
import LevelItShared

/// Watch 端 WatchConnectivity 接收服务
final class WatchSyncReceiver: NSObject {
    static let shared = WatchSyncReceiver()

    private var session: WCSession?
    private var modelContainer: ModelContainer?
    private var configured = false
    private var isActivated = false

    /// 待发送队列
    private var pendingMessages: [[String: Any]] = []

    /// 时间戳去重 (上限 200 条, 超出时清理最旧条目)
    private var lastProcessedTimestamp: [String: TimeInterval] = [:]
    private static let maxDedupEntries = 200

    /// 待用户确认恢复的孤儿任务 ID (iPhone 不存在但 Watch 有)
    private(set) var pendingOrphanTaskIds: [String] = []

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

    // MARK: - 发送

    func sendTask(_ task: DebtTask) {
        var payload = task.toDict()
        payload["_wcType"] = AppConstants.WCMessageType.taskSync
        payload["_wcTimestamp"] = Date().timeIntervalSince1970
        sendReliable(payload)
    }

    func sendProgress(taskId: String, burned: Int, percent: Int, duration: Int) {
        guard let session, isActivated else { return }
        let payload: [String: Any] = [
            "_wcType": AppConstants.WCMessageType.progressUpdate,
            "_wcTimestamp": Date().timeIntervalSince1970,
            "taskId": taskId,
            "burned": burned,
            "percent": percent,
            "duration": duration,
        ]
        // 双通道同时发: sendMessage (实时) + applicationContext (后台)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
        }
        try? session.updateApplicationContext(payload)
    }

    /// 仅走 sendMessage 实时通道 (每秒调用, 不碰 applicationContext)
    func sendProgressRealtime(taskId: String, burned: Int, percent: Int, duration: Int) {
        guard let session, isActivated, session.isReachable else { return }
        let payload: [String: Any] = [
            "_wcType": AppConstants.WCMessageType.progressUpdate,
            "_wcTimestamp": Date().timeIntervalSince1970,
            "taskId": taskId,
            "burned": burned,
            "percent": percent,
            "duration": duration,
        ]
        session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
    }

    func sendStatusUpdate(taskId: String, status: TaskStatus, task: DebtTask? = nil) {
        if let task {
            var payload = task.toDict()
            payload["_wcType"] = AppConstants.WCMessageType.taskSync
            payload["_wcTimestamp"] = Date().timeIntervalSince1970
            sendReliable(payload)
        } else {
            let payload: [String: Any] = [
                "_wcType": AppConstants.WCMessageType.taskSync,
                "_wcTimestamp": Date().timeIntervalSince1970,
                "id": taskId,
                "status": status.rawValue,
                "_statusOnly": true,
            ]
            sendReliable(payload)
        }
    }

    private func sendReliable(_ payload: [String: Any]) {
        guard let session, isActivated else {
            pendingMessages.append(payload)
            return
        }
        session.transferUserInfo(payload)
    }

    private func flushPendingMessages() {
        let messages = pendingMessages
        pendingMessages.removeAll()
        for msg in messages {
            sendReliable(msg)
        }
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

    private func autoCompleteIfNeeded(_ task: DebtTask) {
        guard task.burnedCalories >= task.targetBurnCalories else { return }
        guard task.status == .inProgress || task.status == .paused else { return }
        // paused → completed 不合法, 需先恢复到 inProgress
        if task.status == .paused {
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
    private func handleIncomingTask(_ message: [String: Any]) {
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
                TaskStateMachine.transition(existing, to: status)
                if let b = message["burnedCalories"] as? Int { existing.burnedCalories = max(existing.burnedCalories, b) }
                if let p = message["progressPercent"] as? Int { existing.progressPercent = max(existing.progressPercent, p) }
                if let d = message["durationSeconds"] as? Int { existing.durationSeconds = max(existing.durationSeconds, d) }
                if let ts = message["completedAt"] as? TimeInterval { existing.completedAt = Date(timeIntervalSince1970: ts) }
                if status == .settled && existing.completedAt == nil {
                    existing.completedAt = Date()
                }
                try? context.save()
            }
            return
        }

        if let existing = allTasks.first(where: { $0.id == taskId }) {
            mergeDefinitionFields(into: existing, from: message)
            if let statusRaw = message["status"] as? String,
               let status = TaskStatus(rawValue: statusRaw) {
                TaskStateMachine.transition(existing, to: status)
            }
            existing.burnedCalories = max(existing.burnedCalories, message["burnedCalories"] as? Int ?? 0)
            existing.progressPercent = max(existing.progressPercent, message["progressPercent"] as? Int ?? 0)
            existing.durationSeconds = max(existing.durationSeconds, message["durationSeconds"] as? Int ?? 0)
            existing.isOverAchieved = message["isOverAchieved"] as? Bool ?? existing.isOverAchieved
            if let ts = message["completedAt"] as? TimeInterval { existing.completedAt = Date(timeIntervalSince1970: ts) }
            if existing.status == .settled && existing.completedAt == nil {
                existing.completedAt = Date()
            }
            existing.lastSyncAt = Date()
            autoCompleteIfNeeded(existing)
        } else {
            if let newTask = DebtTask.fromDict(message) {
                context.insert(newTask)
                try? context.save()
                // 通知 UI 有新任务到达
                NotificationCenter.default.post(
                    name: .newTaskFromiPhone,
                    object: nil,
                    userInfo: ["taskId": newTask.id, "foodName": newTask.foodName, "foodEmoji": newTask.foodEmoji, "kcal": newTask.estimatedCalories]
                )
                return
            }
        }
        try? context.save()
    }

    @MainActor
    private func routeMessage(_ message: [String: Any]) {
        let type = message["_wcType"] as? String
        switch type {
        case AppConstants.WCMessageType.taskDelete:
            handleDeleteTask(message)
        case AppConstants.WCMessageType.reconcile:
            handleReconcile(message)
        case AppConstants.WCMessageType.intakeSummary:
            handleIntakeSummary(message)
        default:
            handleIncomingTask(message)
        }
    }

    /// 处理 iPhone 推送的"今日摄入摘要"
    @MainActor
    private func handleIntakeSummary(_ message: [String: Any]) {
        let kcal = message[AppConstants.WCPayloadKey.todayIntakeKcal] as? Int ?? 0
        let count = message[AppConstants.WCPayloadKey.todayIntakeCount] as? Int ?? 0
        let ts = message["_wcTimestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        WatchTodayIntakeStore.shared.update(
            kcal: kcal,
            count: count,
            at: Date(timeIntervalSince1970: ts)
        )
    }

    /// 对账: 检查 iPhone 上不存在的本地任务, 交由用户确认处理
    /// 同时把 Watch 端活跃任务推回 iPhone, 让双方 max() 收敛
    @MainActor
    private func handleReconcile(_ message: [String: Any]) {
        guard let activeIds = message["activeTaskIds"] as? [String] else { return }
        guard let container = modelContainer else { return }

        let activeIdSet = Set(activeIds)
        let context = container.mainContext
        let allTasks = (try? context.fetch(FetchDescriptor<DebtTask>())) ?? []

        // 1. 把 iPhone 缺失的任务推回去 (含终态, 让双方数据一致)
        let missingOnPhone = allTasks.filter { !activeIdSet.contains($0.id) }
        for task in missingOnPhone {
            sendTask(task)
        }

        // 2. iPhone 已有的活跃任务也推回 (双向 max 收敛 burnedCalories)
        let activeOnBoth = allTasks.filter { !$0.status.isTerminal && activeIdSet.contains($0.id) }
        for task in activeOnBoth {
            sendTask(task)
        }
    }

    // MARK: - 孤儿任务恢复

    /// 用户确认: 把孤儿任务推送到 iPhone
    @MainActor
    func confirmRecovery() {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let allTasks = (try? context.fetch(FetchDescriptor<DebtTask>())) ?? []

        let orphanIdSet = Set(pendingOrphanTaskIds)
        for task in allTasks where orphanIdSet.contains(task.id) {
            sendTask(task)
        }
        pendingOrphanTaskIds = []
    }

    /// 用户拒绝: 删除孤儿任务
    @MainActor
    func declineRecovery() {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let allTasks = (try? context.fetch(FetchDescriptor<DebtTask>())) ?? []

        let orphanIdSet = Set(pendingOrphanTaskIds)
        var deleted = false
        for task in allTasks where orphanIdSet.contains(task.id) {
            context.delete(task)
            deleted = true
        }
        if deleted {
            try? context.save()
        }
        pendingOrphanTaskIds = []
    }

    @MainActor
    private func handleDeleteTask(_ message: [String: Any]) {
        guard let taskId = message["id"] as? String else { return }
        guard let container = modelContainer else { return }

        let context = container.mainContext
        let allTasks = (try? context.fetch(FetchDescriptor<DebtTask>())) ?? []
        guard let task = allTasks.first(where: { $0.id == taskId }) else { return }

        // 1. 先广播"即将删除"，让 UI 主动弹掉对此 task 的 navigation/sheet 引用，
        //    避免 SwiftData invalidate 后视图访问已失效模型导致闪退。
        NotificationCenter.default.post(
            name: .taskWillBeDeletedOnWatch,
            object: nil,
            userInfo: ["taskId": taskId]
        )

        // 2. 让 UI 至少跑一帧来消化 navigation 弹栈，再实际从 SwiftData 删除。
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            // 重新 fetch 以防中间已经被其它路径删除
            let stillAllTasks = (try? context.fetch(FetchDescriptor<DebtTask>())) ?? []
            if let stillTask = stillAllTasks.first(where: { $0.id == taskId }) {
                context.delete(stillTask)
                try? context.save()
            }
            _ = task // 显式持有局部引用避免提前释放（防御性）
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncReceiver: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            isActivated = true
            flushPendingMessages()
            requestFullSync()
        }
    }

    /// Watch 激活后请求 iPhone 推送全量任务 (解决新安装后无数据问题)
    private func requestFullSync() {
        guard let session, session.isReachable else { return }
        let payload: [String: Any] = [
            "_wcType": AppConstants.WCMessageType.requestSync,
            "_wcTimestamp": Date().timeIntervalSince1970,
        ]
        session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
    }

    /// iPhone 可达状态变化时，补发同步请求
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            requestFullSync()
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in routeMessage(userInfo) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in routeMessage(message) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(["_ack": true])
        Task { @MainActor in routeMessage(message) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in routeMessage(applicationContext) }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let newTaskFromiPhone = Notification.Name("newTaskFromiPhone")
    static let orphanTasksDetected = Notification.Name("orphanTasksDetected")
    /// iPhone 推送的"任务即将删除"事件；UI 收到后应先把相关 navigation pop 出栈，
    /// 否则 SwiftData @Model 在 delete 后被 invalidate，正在访问其属性的视图会闪退。
    static let taskWillBeDeletedOnWatch = Notification.Name("taskWillBeDeletedOnWatch")
}
