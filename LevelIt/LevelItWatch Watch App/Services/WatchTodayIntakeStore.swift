import Foundation
import Combine

/// Watch 端"今日摄入摘要"本地缓存
///
/// 数据来自 iPhone 通过 WC applicationContext 推送（WCMessageType.intakeSummary）。
/// 持久化到 UserDefaults，App 重启后立即可用，避免空白等待 WC 同步。
///
/// "今日"判定按 lastUpdate 的日期：跨日时返回 0（避免显示昨日陈旧数据）。
@MainActor
final class WatchTodayIntakeStore: ObservableObject {
    static let shared = WatchTodayIntakeStore()

    @Published private(set) var todayIntakeKcal: Int = 0
    @Published private(set) var todayIntakeCount: Int = 0

    private let kcalKey = "watchTodayIntakeKcal"
    private let countKey = "watchTodayIntakeCount"
    private let dateKey  = "watchTodayIntakeDate"

    private init() {
        loadFromDefaults()
    }

    /// 收到 iPhone 推送时调用
    func update(kcal: Int, count: Int, at date: Date = Date()) {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            todayIntakeKcal = max(0, kcal)
            todayIntakeCount = max(0, count)
        } else {
            todayIntakeKcal = 0
            todayIntakeCount = 0
        }
        UserDefaults.standard.set(todayIntakeKcal, forKey: kcalKey)
        UserDefaults.standard.set(todayIntakeCount, forKey: countKey)
        UserDefaults.standard.set(todayString(date), forKey: dateKey)
    }

    private func loadFromDefaults() {
        let storedDate = UserDefaults.standard.string(forKey: dateKey) ?? ""
        let isToday = storedDate == todayString(Date())
        guard isToday else {
            todayIntakeKcal = 0
            todayIntakeCount = 0
            return
        }
        todayIntakeKcal = max(0, UserDefaults.standard.integer(forKey: kcalKey))
        todayIntakeCount = max(0, UserDefaults.standard.integer(forKey: countKey))
    }

    private func todayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
