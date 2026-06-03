import Testing
import Foundation
@testable import LevelItShared

@Suite("CalorieCalculator Tests")
struct CalorieCalculatorTests {

    // MARK: - 时长计算 (新消耗系数: walk=5.0, mix=8.0, run=11.0)

    @Test("快走模式: 300 kcal / 5.0 = 60 分钟")
    func walkMode() {
        let minutes = CalorieCalculator.calculateMinutes(calories: 300, mode: .walk)
        #expect(minutes == 60)  // ceil(300 / 5.0) = 60
    }

    @Test("标准模式: 300 kcal / 8.0 = 38 分钟")
    func mixMode() {
        let minutes = CalorieCalculator.calculateMinutes(calories: 300, mode: .mix)
        #expect(minutes == 38)  // ceil(300 / 8.0) = ceil(37.5) = 38
    }

    @Test("跑步模式: 300 kcal / 11.0 = 28 分钟")
    func runMode() {
        let minutes = CalorieCalculator.calculateMinutes(calories: 300, mode: .run)
        #expect(minutes == 28)  // ceil(300 / 11.0) = ceil(27.27) = 28
    }

    @Test("最小结果为 1 分钟")
    func minimumOneMinute() {
        let minutes = CalorieCalculator.calculateMinutes(calories: 1, mode: .run)
        #expect(minutes == 1)
    }

    @Test("0 卡路里返回 0")
    func zeroCalories() {
        let minutes = CalorieCalculator.calculateMinutes(calories: 0, mode: .walk)
        #expect(minutes == 0)
    }

    @Test("负值返回 0")
    func negativeCalories() {
        let minutes = CalorieCalculator.calculateMinutes(calories: -100, mode: .walk)
        #expect(minutes == 0)
    }

    // MARK: - 全模式对比

    @Test("基础三种模式: 快走 > 标准 > 跑步 (同等热量, 时间递减)")
    func basicModesDescending() {
        let basic = TaskMode.basicModes
        let results = basic.map { (mode: $0, minutes: CalorieCalculator.calculateMinutes(calories: 300, mode: $0)) }
        #expect(results[0].mode == .walk)
        #expect(results[1].mode == .mix)
        #expect(results[2].mode == .run)
        #expect(results[0].minutes > results[1].minutes)
        #expect(results[1].minutes > results[2].minutes)
    }

    @Test("所有模式都有正数消耗率")
    func allModesPositiveRate() {
        for mode in TaskMode.allCases {
            #expect(mode.caloriesPerMinute > 0, "\(mode.displayName) 消耗率应为正数")
            let minutes = CalorieCalculator.calculateMinutes(calories: 100, mode: mode)
            #expect(minutes >= 1, "\(mode.displayName) 100kcal 至少 1 分钟")
        }
    }

    @Test("calculateAllModes 返回所有模式")
    func allModesReturnsAll() {
        let results = CalorieCalculator.calculateAllModes(calories: 300)
        #expect(results.count == TaskMode.allCases.count)
    }

    // MARK: - 热量校验

    @Test("正常热量范围: 10-5000")
    func validRange() {
        #expect(CalorieCalculator.validateCalories(10) == .valid)
        #expect(CalorieCalculator.validateCalories(300) == .valid)
        #expect(CalorieCalculator.validateCalories(5000) == .valid)
    }

    @Test("clampedCalories 统一限制持久化热量范围")
    func clampedCalories() {
        #expect(CalorieCalculator.clampedCalories(-20) == AppConstants.minCalories)
        #expect(CalorieCalculator.clampedCalories(300) == 300)
        #expect(CalorieCalculator.clampedCalories(9000) == AppConstants.maxCalories)
    }

    @Test("低于 10 kcal 判定为 tooLow")
    func tooLow() {
        #expect(CalorieCalculator.validateCalories(0) == .tooLow)
        #expect(CalorieCalculator.validateCalories(9) == .tooLow)
        #expect(CalorieCalculator.validateCalories(-1) == .tooLow)
    }

    @Test("超过 5000 kcal 判定为 suspicious")
    func suspicious() {
        #expect(CalorieCalculator.validateCalories(5001) == .suspicious)
        #expect(CalorieCalculator.validateCalories(8500) == .suspicious)
    }

    // MARK: - TaskLevel 映射

    @Test("TaskLevel 根据热量正确分档")
    func taskLevelMapping() {
        #expect(TaskLevel.from(calories: 50) == .green)
        #expect(TaskLevel.from(calories: 119) == .green)
        #expect(TaskLevel.from(calories: 120) == .yellow)
        #expect(TaskLevel.from(calories: 219) == .yellow)
        #expect(TaskLevel.from(calories: 220) == .orange)
        #expect(TaskLevel.from(calories: 349) == .orange)
        #expect(TaskLevel.from(calories: 350) == .red)
        #expect(TaskLevel.from(calories: 1000) == .red)
    }

    // MARK: - 新增运动类型

    @Test("室内运动标记正确")
    func indoorFlag() {
        #expect(TaskMode.indoorWalk.isIndoor)
        #expect(TaskMode.indoorRun.isIndoor)
        #expect(TaskMode.indoorCycling.isIndoor)
        #expect(TaskMode.elliptical.isIndoor)
        #expect(TaskMode.swimming.isIndoor)
        #expect(!TaskMode.walk.isIndoor)
        #expect(!TaskMode.run.isIndoor)
        #expect(!TaskMode.cycling.isIndoor)
    }

    @Test("强度值在 0-1 范围内")
    func intensityRange() {
        for mode in TaskMode.allCases {
            #expect(mode.intensity > 0 && mode.intensity <= 1.0,
                    "\(mode.displayName) intensity=\(mode.intensity) 应在 (0, 1]")
        }
    }
}
