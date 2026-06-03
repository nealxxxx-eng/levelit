import SwiftUI
import SwiftData
import WidgetKit
import LevelItShared

@main
struct LevelItWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchTaskInboxView()
        }
        .modelContainer(for: [
            DebtTask.self,
            Achievement.self,
            UserStats.self,
        ])
    }
}
