import Foundation
import SwiftData
import LevelItShared

/// 将本地运动账本映射到 PK 挑战进度，并推送到服务端。
@MainActor
enum PKChallengeProgressService {
    static func refreshForTask(
        taskId: String,
        in modelContext: ModelContext,
        pushRemote: Bool = true
    ) async {
        let challenges = fetchChallenges(in: modelContext).filter { challenge in
            challenge.status == .accepted &&
            (challenge.linkedTaskId == nil || challenge.linkedTaskId == taskId)
        }
        await refresh(challenges: challenges, in: modelContext, pushRemote: pushRemote)
    }

    static func refreshAll(
        in modelContext: ModelContext,
        pushRemote: Bool = true
    ) async {
        let challenges = fetchChallenges(in: modelContext).filter { $0.status == .accepted }
        await refresh(challenges: challenges, in: modelContext, pushRemote: pushRemote)
    }

    private static func refresh(
        challenges: [PKChallenge],
        in modelContext: ModelContext,
        pushRemote: Bool
    ) async {
        guard !challenges.isEmpty else { return }
        let tasks = fetchTasks(in: modelContext)

        for challenge in challenges {
            let progress = await localProgress(for: challenge, tasks: tasks)
            let progressToPush = max(challenge.myProgress, progress)

            if progress > challenge.myProgress {
                challenge.myProgress = progress
                if progress >= challenge.targetCalories {
                    challenge.status = .completed
                    challenge.completedAt = challenge.completedAt ?? Date()
                }
            }

            guard pushRemote, let serverId = challenge.serverId, progressToPush > 0 else { continue }
            let isChallenger = challenge.isChallenger
            let target = challenge.targetCalories

            do {
                let opponentProgress = try await PKSyncService.pushProgress(
                    serverId: serverId,
                    isChallenger: isChallenger,
                    myProgress: progressToPush
                )
                challenge.opponentProgress = max(challenge.opponentProgress, opponentProgress)
                if challenge.opponentProgress >= target {
                    challenge.status = .completed
                    challenge.completedAt = challenge.completedAt ?? Date()
                }
            } catch {
                // PK 同步失败不能影响本地任务结算；下次进入 PK 或刷新时会重试。
            }
        }

        try? modelContext.save()
    }

    /// 计算挑战的本地进度：取「HealthKit 实测运动」与「磨平还债任务账本」的较大值。
    ///
    /// 三种挑战类型统一处理——任何真实运动消耗（含 Apple Watch 等只进 HealthKit、
    /// 不产生还债任务的外部运动）都应计入 PK。此前 firstToSettle / streakSprint 只看
    /// 还债账本，导致纯 HealthKit 运动（如 Apple Watch 力量训练）完全不计入。
    /// 取 max（而非相加）可避免本 App 运动在两个来源里被重复计算。
    private static func localProgress(for challenge: PKChallenge, tasks: [DebtTask]) async -> Int {
        let taskProgress = taskLedgerProgress(for: challenge, tasks: tasks)
        let workoutProgress = await healthKitWorkoutProgress(for: challenge)
        return min(challenge.targetCalories, max(workoutProgress, taskProgress))
    }

    private static func taskLedgerProgress(for challenge: PKChallenge, tasks: [DebtTask]) -> Int {
        let scopedTasks = tasks.filter { task in
            guard countsTowardPK(task) else { return false }
            if let linkedTaskId = challenge.linkedTaskId,
               let linkedTask = tasks.first(where: { $0.id == linkedTaskId }) {
                return Calendar.current.isDate(task.createdAt, inSameDayAs: linkedTask.createdAt)
            }
            return isTask(task, inside: challenge)
        }

        let burned = scopedTasks.reduce(0) { $0 + max(0, $1.burnedCalories) }
        return min(challenge.targetCalories, burned)
    }

    private static func healthKitWorkoutProgress(for challenge: PKChallenge) async -> Int {
        let window = challengeWindow(for: challenge)
        await HealthKitDataStore.shared.refreshPeriodWorkouts(start: window.start, end: window.end, force: true)
        let burned = HealthKitDataStore.shared.periodWorkouts
            .filter { $0.startDate >= window.start && $0.startDate < window.end }
            .reduce(0) { $0 + max(0, $1.calories) }
        return min(challenge.targetCalories, burned)
    }

    private static func countsTowardPK(_ task: DebtTask) -> Bool {
        switch task.status {
        case .inProgress, .paused, .completed, .settled:
            return task.burnedCalories > 0
        case .created, .synced, .cancelled, .expired:
            return false
        }
    }

    private static func isTask(_ task: DebtTask, inside challenge: PKChallenge) -> Bool {
        let (start, end) = challengeWindow(for: challenge)
        guard task.createdAt >= start else { return false }
        return task.createdAt < end
    }

    private static func challengeWindow(for challenge: PKChallenge) -> (start: Date, end: Date) {
        let start = challenge.acceptedAt ?? challenge.createdAt
        let end = Calendar.current.date(
            byAdding: .day,
            value: max(1, challenge.durationDays),
            to: start
        ) ?? start.addingTimeInterval(TimeInterval(max(1, challenge.durationDays)) * 24 * 3600)
        return (start, end)
    }

    private static func fetchChallenges(in modelContext: ModelContext) -> [PKChallenge] {
        (try? modelContext.fetch(FetchDescriptor<PKChallenge>())) ?? []
    }

    private static func fetchTasks(in modelContext: ModelContext) -> [DebtTask] {
        (try? modelContext.fetch(FetchDescriptor<DebtTask>())) ?? []
    }
}
