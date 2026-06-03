import HealthKit

/// 从 HealthKit 读取今日外部运动记录，用于抵扣食物热量
enum HealthKitImportService {

    /// 单条可导入的运动记录
    struct ImportableWorkout: Identifiable {
        let id: UUID
        let activityType: HKWorkoutActivityType
        let calories: Int
        let duration: TimeInterval
        let source: String       // 来源 App 名
        let startDate: Date
        let endDate: Date

        var displayName: String { activityType.displayName }
        var iconName: String { activityType.iconName }
        var durationMinutes: Int { Int(duration / 60) }
    }

    private static let healthStore = HKHealthStore()
    private static let ownBundlePrefix = "xxxx.LevelIt"

    // MARK: - 授权

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 查询今日外部运动

    /// 获取今日所有非本 App 产生的运动记录
    static func fetchTodayExternalWorkouts() async -> [ImportableWorkout] {
        guard isAvailable else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let external = workouts.compactMap { workout -> ImportableWorkout? in
                    let bundle = workout.sourceRevision.source.bundleIdentifier
                    // 排除本 App（iPhone + Watch）产生的运动
                    if bundle.hasPrefix(ownBundlePrefix) { return nil }

                    let energyType = HKQuantityType(.activeEnergyBurned)
                    let calories = Int(workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
                    guard calories > 0 else { return nil }

                    return ImportableWorkout(
                        id: workout.uuid,
                        activityType: workout.workoutActivityType,
                        calories: calories,
                        duration: workout.duration,
                        source: workout.sourceRevision.source.name,
                        startDate: workout.startDate,
                        endDate: workout.endDate
                    )
                }

                continuation.resume(returning: external)
            }
            healthStore.execute(query)
        }
    }

    /// 今日外部运动总消耗
    static func fetchTodayExternalCalories() async -> Int {
        let workouts = await fetchTodayExternalWorkouts()
        return workouts.reduce(0) { $0 + $1.calories }
    }

    // MARK: - 统计用：查询时间段内所有运动

    /// 统计用运动摘要（含 LevelIt 自身运动）
    struct WorkoutSummary: Identifiable {
        let id: UUID
        let activityType: HKWorkoutActivityType
        let calories: Int
        let duration: TimeInterval
        let source: String
        let startDate: Date
        let isLevelIt: Bool

        var displayName: String { activityType.displayName }
        var iconName: String { activityType.iconName }
        var durationMinutes: Int { Int(duration / 60) }
    }

    /// 查询指定时间段内所有运动记录（系统 + 磨平 App）
    static func fetchWorkoutsInRange(start: Date, end: Date) async -> [WorkoutSummary] {
        guard isAvailable else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let summaries = workouts.compactMap { workout -> WorkoutSummary? in
                    let energyType = HKQuantityType(.activeEnergyBurned)
                    let calories = Int(workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
                    guard calories > 0 else { return nil }

                    let bundle = workout.sourceRevision.source.bundleIdentifier
                    return WorkoutSummary(
                        id: workout.uuid,
                        activityType: workout.workoutActivityType,
                        calories: calories,
                        duration: workout.duration,
                        source: workout.sourceRevision.source.name,
                        startDate: workout.startDate,
                        isLevelIt: bundle.hasPrefix(ownBundlePrefix)
                    )
                }

                continuation.resume(returning: summaries)
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - HKWorkoutActivityType 显示名

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running:                return "跑步"
        case .walking:                return "步行"
        case .cycling:                return "骑行"
        case .swimming:               return "游泳"
        case .yoga:                   return "瑜伽"
        case .functionalStrengthTraining: return "力量训练"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining:           return "核心训练"
        case .elliptical:             return "椭圆机"
        case .rowing:                 return "划船机"
        case .dance:                  return "舞蹈"
        case .cooldown:               return "拉伸"
        case .mixedCardio:            return "混合有氧"
        case .traditionalStrengthTraining: return "传统力量"
        case .stairClimbing:          return "爬楼梯"
        case .jumpRope:               return "跳绳"
        default:                      return "运动"
        }
    }

    var iconName: String {
        switch self {
        case .running:                return "figure.run"
        case .walking:                return "figure.walk"
        case .cycling:                return "figure.outdoor.cycle"
        case .swimming:               return "figure.pool.swim"
        case .yoga:                   return "figure.yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining:
                                      return "figure.strengthtraining.functional"
        case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
        case .coreTraining:           return "figure.core.training"
        case .elliptical:             return "figure.elliptical"
        case .rowing:                 return "figure.rower"
        case .dance:                  return "figure.dance"
        case .jumpRope:               return "figure.jumprope"
        case .stairClimbing:          return "figure.stair.stepper"
        default:                      return "figure.mixed.cardio"
        }
    }
}
