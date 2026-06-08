import SwiftUI
import SwiftData
import LevelItShared
import UserNotifications

@main
struct LevelItApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: DebtTask.self,
                Achievement.self,
                UserStats.self,
                PKChallenge.self,
                AnomalyLog.self,
                MealIntake.self,
                ImportedWorkoutRecord.self,
                DailyCalorieBalance.self
            )
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await NotificationScheduler.requestAndSchedule()
                    // 申请远程通知权限后，系统回调 AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken
                    let granted = (try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                    if granted {
                        await MainActor.run {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                    await MainActor.run {
                        AppLifecycleCoordinator.shared.appDidLaunch(container: container)
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                WCSyncService.shared.handleEnterForeground()
                AppLifecycleCoordinator.shared.handleBecameActive(container: container)
            case .background:
                WCSyncService.shared.handleEnterBackground()
            default:
                break
            }
        }
    }
}

// MARK: - AppDelegate (APNs device token)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        PKDeviceTokenStore.save(tokenString)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // 模拟器上正常失败，无需处理
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
}

// MARK: - Device token 存储

enum PKDeviceTokenStore {
    private static let key = "pk_apns_device_token"

    static var current: String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func save(_ token: String) {
        UserDefaults.standard.set(token, forKey: key)
        // 将 token 注册到所有进行中的挑战（fire-and-forget）
        Task { await registerTokenForActiveChallenges(token) }
    }

    @MainActor
    private static func registerTokenForActiveChallenges(_ token: String) async {
        // 通过 NotificationCenter 广播给需要它的 Service
        NotificationCenter.default.post(
            name: .pkDeviceTokenUpdated,
            object: token
        )
    }
}

extension Notification.Name {
    static let pkDeviceTokenUpdated = Notification.Name("PKDeviceTokenUpdated")
}
