import Foundation

/// 运动模式 — 对应 Apple Watch 原生运动类型
public enum TaskMode: String, Codable, CaseIterable, Sendable {
    // 基础三种 (向下兼容)
    case walk           // 户外快走
    case mix            // 跑走结合
    case run            // 户外跑步

    // 扩展运动类型
    case indoorWalk     // 室内步行 (跑步机)
    case indoorRun      // 室内跑步 (跑步机)
    case cycling        // 户外骑行
    case indoorCycling  // 室内单车
    case elliptical     // 椭圆机
    case rowing         // 划船机
    case coreTraining   // 核心训练
    case functionalTraining // 自由训练/HIIT
    case swimming       // 泳池游泳

    /// 中文显示名
    public var displayName: String {
        switch self {
        case .walk:               return "户外快走"
        case .mix:                return "跑走结合"
        case .run:                return "户外跑步"
        case .indoorWalk:         return "室内步行"
        case .indoorRun:          return "室内跑步"
        case .cycling:            return "户外骑行"
        case .indoorCycling:      return "室内单车"
        case .elliptical:         return "椭圆机"
        case .rowing:             return "划船机"
        case .coreTraining:       return "核心训练"
        case .functionalTraining: return "自由训练"
        case .swimming:           return "泳池游泳"
        }
    }

    /// 运动描述
    public var description: String {
        switch self {
        case .walk:               return "户外快走"
        case .mix:                return "跑走结合"
        case .run:                return "户外跑步/跳绳"
        case .indoorWalk:         return "跑步机步行"
        case .indoorRun:          return "跑步机跑步"
        case .cycling:            return "户外自行车"
        case .indoorCycling:      return "动感单车"
        case .elliptical:         return "椭圆机/交叉训练"
        case .rowing:             return "划船机"
        case .coreTraining:       return "核心/腹肌训练"
        case .functionalTraining: return "力量/HIIT/自由训练"
        case .swimming:           return "泳池游泳"
        }
    }

    /// 每分钟消耗 kcal (估算)
    public var caloriesPerMinute: Double {
        switch self {
        case .walk:               return 5.0
        case .indoorWalk:         return 4.5
        case .mix:                return 8.0
        case .run:                return 11.0
        case .indoorRun:          return 10.0
        case .cycling:            return 9.0
        case .indoorCycling:      return 8.5
        case .elliptical:         return 7.5
        case .rowing:             return 8.0
        case .coreTraining:       return 6.0
        case .functionalTraining: return 9.0
        case .swimming:           return 10.0
        }
    }

    /// SF Symbol 图标
    public var iconName: String {
        switch self {
        case .walk, .indoorWalk:         return "figure.walk"
        case .mix:                       return "figure.run"
        case .run, .indoorRun:           return "figure.run.circle.fill"
        case .cycling, .indoorCycling:   return "figure.outdoor.cycle"
        case .elliptical:                return "figure.elliptical"
        case .rowing:                    return "figure.rower"
        case .coreTraining:              return "figure.core.training"
        case .functionalTraining:        return "figure.strengthtraining.functional"
        case .swimming:                  return "figure.pool.swim"
        }
    }

    /// 运动强度 (0-1, 用于 UI 强度条)
    public var intensity: Double {
        switch self {
        case .indoorWalk, .walk:         return 0.2
        case .coreTraining:              return 0.35
        case .elliptical:                return 0.45
        case .mix, .rowing, .indoorCycling: return 0.55
        case .cycling, .functionalTraining: return 0.7
        case .indoorRun, .swimming:      return 0.85
        case .run:                       return 1.0
        }
    }

    /// 是否室内运动
    public var isIndoor: Bool {
        switch self {
        case .indoorWalk, .indoorRun, .indoorCycling, .elliptical, .rowing, .coreTraining, .functionalTraining, .swimming:
            return true
        default:
            return false
        }
    }

    /// 推荐的基础模式 (iPhone 创建任务时默认显示的 3 种)
    public static var basicModes: [TaskMode] {
        [.walk, .mix, .run]
    }

    /// 全部模式按强度排序
    public static var allByIntensity: [TaskMode] {
        allCases.sorted { $0.intensity < $1.intensity }
    }
}
