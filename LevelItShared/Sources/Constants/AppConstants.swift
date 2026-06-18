import Foundation

/// 全局常量
public enum AppConstants {
    /// App 名称
    public static let appName = "磨平"
    public static let appNameEnglish = "LevelIt"

    /// 超额完成阈值 (120%)
    public static let overAchievementThreshold: Double = 1.2

    /// 热量校验范围
    public static let minCalories: Int = 10
    public static let maxCalories: Int = 5000

    /// 多人分餐提示阈值 (kcal)：超过此值自动弹出分餐选项
    public static let sharedMealThreshold: Int = 800

    /// 每日加餐缓冲上限。加餐/饮料超过缓冲的部分才建议进入磨平任务。
    public static let maxDailySnackBuffer: Int = 250

    /// 餐次时段边界的模糊区（分钟）：拍照时间落在正餐窗口 start/end ±此值内，提示用户选「正餐/加餐」
    public static let mealEdgeMinutes: Int = 30

    /// Watch 运动进度推送频率 (秒)
    public static let watchProgressSyncInterval: TimeInterval = 5.0

    /// 励志文案更换频率 (秒)
    public static let quoteRotationInterval: TimeInterval = 300  // 5 分钟

    /// Watch UI 刷新节流 (秒)
    public static let watchUIThrottleInterval: TimeInterval = 1.0

    /// 食物图片最大尺寸 (bytes)
    public static let maxFoodImageSize: Int = 1_048_576  // 1 MB

    /// 分享卡最大分辨率
    public static let shareCardMaxWidth: CGFloat = 1080

    /// Complication 颜色阈值
    public enum ComplicationThreshold {
        public static let green: Int = 200    // < 200 kcal
        public static let yellow: Int = 400   // 200-400 kcal
        public static let orange: Int = 600   // 400-600 kcal
        // > 600 kcal = red
    }

    /// WC 消息类型标识
    public enum WCMessageType {
        public static let taskSync = "task_sync"
        public static let taskDelete = "task_delete"
        public static let progressUpdate = "progress"
        public static let uiRefresh = "ui_refresh"
        public static let requestSync = "request_sync"
        public static let reconcile = "reconcile"
        /// iPhone → Watch 推送当日摄入摘要（applicationContext 镜像）
        public static let intakeSummary = "intake_summary"
    }

    /// WC payload 字段名
    public enum WCPayloadKey {
        /// MealIntake 当日总和（int kcal）
        public static let todayIntakeKcal = "todayIntakeKcal"
        /// 当日摄入条目数
        public static let todayIntakeCount = "todayIntakeCount"
    }

    /// 用户档案默认值
    public enum ProfileDefaults {
        public static let minAge: Int = 12
        public static let maxAge: Int = 80
        public static let defaultAge: Int = 30
        public static let minHeightCM: Int = 120
        public static let maxHeightCM: Int = 220
        public static let defaultHeightCM: Int = 170
        public static let minWeightKG: Double = 30
        public static let maxWeightKG: Double = 200
        public static let defaultWeightKG: Double = 65
        public static let minDailyEnergyEstimate: Int = 800
        public static let maxDailyEnergyEstimate: Int = 6000
    }

    /// Mock 运动模拟器参数
    public enum MockWorkout {
        public static let minCaloriesPerSecond: Double = 8.0 / 60.0   // 约 8 kcal/min
        public static let maxCaloriesPerSecond: Double = 15.0 / 60.0  // 约 15 kcal/min
    }
}
