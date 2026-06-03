import Testing
import Foundation
@testable import LevelItShared

@Suite("Workout Import Model Tests")
struct WorkoutImportModelsTests {

    @Test("DailyCalorieBalance.todayKey 使用本地日历日")
    func todayKeyUsesCalendarDay() {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 17
        components.hour = 9
        components.minute = 30
        let date = Calendar.current.date(from: components)!

        #expect(DailyCalorieBalance.todayKey(date: date) == "2026-05-17")
    }

    @Test("Workout import models clamp negative values")
    func importedWorkoutModelClampsNegativeValues() {
        let record = ImportedWorkoutRecord(id: "workout-1", calories: -10, durationSeconds: -30)
        let balance = DailyCalorieBalance(calories: -20, durationSeconds: -60)

        #expect(record.calories == 0)
        #expect(record.durationSeconds == 0)
        #expect(balance.calories == 0)
        #expect(balance.durationSeconds == 0)
    }
}
