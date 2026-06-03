import Foundation
import SwiftData

/// External workout UUIDs that have already been imported into LevelIt.
@Model
public final class ImportedWorkoutRecord {
    @Attribute(.unique) public var id: String
    public var dateKey: String
    public var calories: Int
    public var durationSeconds: Int
    public var importedAt: Date

    public init(
        id: String,
        dateKey: String = DailyCalorieBalance.todayKey(),
        calories: Int = 0,
        durationSeconds: Int = 0,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.dateKey = dateKey
        self.calories = max(0, calories)
        self.durationSeconds = max(0, durationSeconds)
        self.importedAt = importedAt
    }
}

/// Remaining external workout calories available for today's task offset.
@Model
public final class DailyCalorieBalance {
    @Attribute(.unique) public var dateKey: String
    public var calories: Int
    public var durationSeconds: Int
    public var updatedAt: Date

    public init(
        dateKey: String = DailyCalorieBalance.todayKey(),
        calories: Int = 0,
        durationSeconds: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.dateKey = dateKey
        self.calories = max(0, calories)
        self.durationSeconds = max(0, durationSeconds)
        self.updatedAt = updatedAt
    }

    public static func todayKey(date: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
