import Foundation
import SwiftData

/// 核心任务模型 — 一次"食物债务"从创建到结清的完整生命周期
///
/// 数据流:
///   iPhone 拍照/手选 -> 创建 DebtTask -> WC 同步到 Watch
///   Watch 快选 -> 创建 DebtTask -> WC 同步到 iPhone
///   运动中: Watch 更新 burnedCalories/progressPercent/durationSeconds
///   完成后: status -> completed -> settled
///
@Model
public final class DebtTask {
    @Attribute(.unique) public var id: String
    public var debtType: DebtType
    public var foodName: String
    public var foodEmoji: String
    public var foodImageFileName: String?  // 文件系统引用: Documents/FoodImages/{id}.heic
    public var estimatedCalories: Int
    public var taskLevel: TaskLevel
    public var taskMode: TaskMode
    public var targetBurnCalories: Int
    public var estimatedMinutes: Int
    public var status: TaskStatus
    public var progressPercent: Int
    public var burnedCalories: Int
    public var durationSeconds: Int
    public var lastSyncAt: Date?
    public var createdAt: Date
    public var completedAt: Date?
    public var expiredAt: Date?
    public var source: TaskSource
    public var isOverAchieved: Bool

    public init(
        id: String = UUID().uuidString,
        debtType: DebtType = .food,
        foodName: String,
        foodEmoji: String = "",
        foodImageFileName: String? = nil,
        estimatedCalories: Int,
        taskMode: TaskMode,
        source: TaskSource
    ) {
        self.id = id
        self.debtType = debtType
        self.foodName = foodName
        self.foodEmoji = foodEmoji
        self.foodImageFileName = foodImageFileName
        let safeCalories = CalorieCalculator.clampedCalories(estimatedCalories)
        self.estimatedCalories = safeCalories
        self.taskLevel = TaskLevel.from(calories: safeCalories)
        self.taskMode = taskMode
        self.targetBurnCalories = safeCalories
        self.estimatedMinutes = CalorieCalculator.calculateMinutes(
            calories: safeCalories,
            mode: taskMode
        )
        self.status = .created
        self.progressPercent = 0
        self.burnedCalories = 0
        self.durationSeconds = 0
        self.lastSyncAt = nil
        self.createdAt = Date()
        self.completedAt = nil
        self.expiredAt = nil
        self.source = source
        self.isOverAchieved = false
    }

    /// 更新运动进度
    public func updateProgress(burnedCalories: Int, durationSeconds: Int) {
        self.burnedCalories = burnedCalories
        self.durationSeconds = durationSeconds
        self.lastSyncAt = Date()

        guard targetBurnCalories > 0 else { return }
        self.progressPercent = min(999, Int(Double(burnedCalories) / Double(targetBurnCalories) * 100))

        if burnedCalories >= targetBurnCalories {
            self.isOverAchieved = Double(burnedCalories) >= Double(targetBurnCalories) * 1.2
        }
    }

    /// 是否已经真实达到本任务要求的消耗目标。
    public var hasMetBurnTarget: Bool {
        targetBurnCalories > 0 && burnedCalories >= targetBurnCalories
    }

    /// 今日待执行任务只在创建当天有效；历史欠单留在账本里，不滚入新一天。
    public func isPendingForDay(
        _ referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        status.countsAsDebt && calendar.isDate(createdAt, inSameDayAs: referenceDate)
    }

    /// 未开始的跨日任务归档为过期记录；进行中/暂停任务保留进度，但也不会进入今日待办。
    public func shouldExpireForNewDay(
        _ referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard status == .created || status == .synced else { return false }
        return createdAt < calendar.startOfDay(for: referenceDate)
    }

    /// 转为字典 (用于 WC 传输)
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "debtType": debtType.rawValue,
            "foodName": foodName,
            "foodEmoji": foodEmoji,
            "estimatedCalories": estimatedCalories,
            "taskLevel": taskLevel.rawValue,
            "taskMode": taskMode.rawValue,
            "targetBurnCalories": targetBurnCalories,
            "estimatedMinutes": estimatedMinutes,
            "status": status.rawValue,
            "progressPercent": progressPercent,
            "burnedCalories": burnedCalories,
            "durationSeconds": durationSeconds,
            "createdAt": createdAt.timeIntervalSince1970,
            "source": source.rawValue,
            "isOverAchieved": isOverAchieved,
        ]
        if let fileName = foodImageFileName { dict["foodImageFileName"] = fileName }
        if let syncAt = lastSyncAt { dict["lastSyncAt"] = syncAt.timeIntervalSince1970 }
        if let compAt = completedAt { dict["completedAt"] = compAt.timeIntervalSince1970 }
        if let expAt = expiredAt { dict["expiredAt"] = expAt.timeIntervalSince1970 }
        return dict
    }

    /// 从字典恢复 (用于 WC 接收)
    public static func fromDict(_ dict: [String: Any]) -> DebtTask? {
        guard
            let id = dict["id"] as? String,
            let foodName = dict["foodName"] as? String,
            let estimatedCalories = dict["estimatedCalories"] as? Int,
            let modeRaw = dict["taskMode"] as? String,
            let mode = TaskMode(rawValue: modeRaw),
            let sourceRaw = dict["source"] as? String,
            let source = TaskSource(rawValue: sourceRaw)
        else { return nil }

        let task = DebtTask(
            id: id,
            foodName: foodName,
            foodEmoji: dict["foodEmoji"] as? String ?? "",
            estimatedCalories: estimatedCalories,
            taskMode: mode,
            source: source
        )

        if let statusRaw = dict["status"] as? String,
           let status = TaskStatus(rawValue: statusRaw) {
            task.status = status
        }
        task.progressPercent = dict["progressPercent"] as? Int ?? 0
        task.burnedCalories = dict["burnedCalories"] as? Int ?? 0
        task.durationSeconds = dict["durationSeconds"] as? Int ?? 0
        task.isOverAchieved = dict["isOverAchieved"] as? Bool ?? false
        task.foodImageFileName = dict["foodImageFileName"] as? String
        if let debtTypeRaw = dict["debtType"] as? String,
           let debtType = DebtType(rawValue: debtTypeRaw) {
            task.debtType = debtType
        }

        if let levelRaw = dict["taskLevel"] as? String,
           let level = TaskLevel(rawValue: levelRaw) {
            task.taskLevel = level
        }
        task.targetBurnCalories = CalorieCalculator.clampedCalories(dict["targetBurnCalories"] as? Int ?? task.estimatedCalories)
        task.estimatedMinutes = dict["estimatedMinutes"] as? Int ?? CalorieCalculator.calculateMinutes(calories: task.estimatedCalories, mode: mode)

        if let ts = dict["createdAt"] as? TimeInterval {
            task.createdAt = Date(timeIntervalSince1970: ts)
        }
        if let ts = dict["completedAt"] as? TimeInterval {
            task.completedAt = Date(timeIntervalSince1970: ts)
        }
        if let ts = dict["expiredAt"] as? TimeInterval {
            task.expiredAt = Date(timeIntervalSince1970: ts)
        }
        if let ts = dict["lastSyncAt"] as? TimeInterval {
            task.lastSyncAt = Date(timeIntervalSince1970: ts)
        }

        return task
    }
}
