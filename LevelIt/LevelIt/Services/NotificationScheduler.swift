import UserNotifications

/// 每日 3 次本地通知（早 8 / 午 12 / 晚 8），提醒用户查看运动和磨平进度
enum NotificationScheduler {

    private static let center = UNUserNotificationCenter.current()

    struct ScheduleItem {
        let id: String
        let hour: Int
        let title: String
        let body: String
    }

    private static let schedules: [ScheduleItem] = [
        ScheduleItem(id: "levelit_morning", hour: 8,
                     title: "早安",
                     body: "看看昨晚有没有运动记录可以抵扣？"),
        ScheduleItem(id: "levelit_noon", hour: 12,
                     title: "午间提醒",
                     body: "中午吃了什么？拍一下，顺便看看今日运动进度"),
        ScheduleItem(id: "levelit_evening", hour: 20,
                     title: "晚间盘点",
                     body: "今天的债还清了吗？打开看看运动抵扣情况"),
    ]

    // MARK: - 请求权限 + 调度

    static func requestAndSchedule() async {
        let granted = await requestPermission()
        guard granted else { return }
        scheduleDaily()
    }

    static func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - 调度每日通知

    static func scheduleDaily() {
        // 先清除旧的，避免重复
        center.removePendingNotificationRequests(withIdentifiers: schedules.map(\.id))

        for item in schedules {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = item.hour
            dateComponents.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)

            center.add(request)
        }
    }

    // MARK: - 取消所有通知

    static func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: schedules.map(\.id))
    }
}
