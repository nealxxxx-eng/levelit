import Foundation
import SwiftData
import LevelItShared

/// 把一条"未磨平"的摄入转成磨平任务，并用今日尚未被债务消费的运动**立即抵扣**。
///
/// 账本口径（保守、绝不超发）：
///   可用余额 = max(0, E − D)
///   E = 今日 HealthKit 活动能量合计（含本 App + 外部运动）
///   D = 今日已生成债务任务的 burnedCalories 合计（已被运动还掉的部分）
/// 决策（offset / 终态）委托纯函数 `IntakeOffsetPlan`，本服务只负责取数 + 落库 + 状态机。
@MainActor
enum IntakeOffsetService {

    struct Preview {
        let target: Int
        let available: Int
        let plan: IntakeOffsetPlan.Result
    }

    /// 今日可用运动余额。
    static func availableToday(in ctx: ModelContext) async -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        await HealthKitDataStore.shared.refreshTodayWorkoutSummaries(force: true)
        let E = HealthKitDataStore.shared.todayWorkoutSummaries.reduce(0) { $0 + max(0, $1.calories) }
        let tasks = (try? ctx.fetch(FetchDescriptor<DebtTask>())) ?? []
        let D = tasks
            .filter { $0.createdAt >= start }
            .reduce(0) { $0 + max(0, $1.burnedCalories) }
        return max(0, E - D)
    }

    static func preview(for intake: MealIntake, in ctx: ModelContext) async -> Preview {
        let target = intake.estimatedCalories
        let avail = await availableToday(in: ctx)
        return Preview(
            target: target,
            available: avail,
            plan: IntakeOffsetPlan.plan(target: target, available: avail)
        )
    }

    /// 生成磨平任务并立即用今日运动抵扣，回写 `intake.debtTaskId`，同步 Watch。
    @discardableResult
    static func offset(intake: MealIntake, in ctx: ModelContext) async -> DebtTask {
        let target = intake.estimatedCalories
        let avail = await availableToday(in: ctx)
        let plan = IntakeOffsetPlan.plan(target: target, available: avail)

        let task = DebtTask(
            foodName: intake.foodName,
            foodEmoji: intake.foodEmoji,
            estimatedCalories: target,
            taskMode: .mix,
            source: .iPhone
        )
        if plan.offset > 0 {
            task.updateProgress(burnedCalories: plan.offset, durationSeconds: 0)
        }
        ctx.insert(task)

        // 按 plan 的目标终态逐步走 FSM（completed/settled 需 hasMetBurnTarget，offset≥target 时成立）
        switch plan.finalStatus {
        case .settled:
            _ = TaskStateMachine.transition(task, to: .inProgress)
            _ = TaskStateMachine.transition(task, to: .completed)
            _ = TaskStateMachine.transition(task, to: .settled)
        case .inProgress:
            _ = TaskStateMachine.transition(task, to: .inProgress)
        default:
            break  // created：今日无可用运动，等同普通待磨平任务
        }

        intake.debtTaskId = task.id
        try? ctx.save()
        WCSyncService.shared.sendTaskSnapshot(task)
        WCSyncService.shared.pushTodayIntakeContext(modelContext: ctx)
        return task
    }
}
