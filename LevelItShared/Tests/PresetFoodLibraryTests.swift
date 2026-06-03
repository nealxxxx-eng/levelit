import Testing
import Foundation
@testable import LevelItShared

@Suite("PresetFoodLibrary Tests")
struct PresetFoodLibraryTests {

    @Test("食物库至少包含 30 种食物")
    func minimumFoodCount() {
        #expect(PresetFoodLibrary.allFoods.count >= 30)
    }

    @Test("所有分类都有食物")
    func allCategoriesHaveFoods() {
        for category in FoodCategory.allCases {
            let foods = PresetFoodLibrary.foods(for: category)
            #expect(!foods.isEmpty, "\(category.rawValue) 分类应有食物")
        }
    }

    @Test("所有食物 id 唯一")
    func uniqueIds() {
        let ids = PresetFoodLibrary.allFoods.map(\.id)
        #expect(Set(ids).count == ids.count, "存在重复 id")
    }

    @Test("所有食物热量在合理范围 (10-5000)")
    func caloriesInRange() {
        for food in PresetFoodLibrary.allFoods {
            #expect(food.estimatedCalories >= 10,
                    "\(food.name) 热量太低: \(food.estimatedCalories)")
            #expect(food.estimatedCalories <= 5000,
                    "\(food.name) 热量太高: \(food.estimatedCalories)")
        }
    }

    @Test("所有食物名称非空")
    func nonEmptyNames() {
        for food in PresetFoodLibrary.allFoods {
            #expect(!food.name.isEmpty)
        }
    }

    @Test("所有食物 emoji 非空")
    func nonEmptyEmoji() {
        for food in PresetFoodLibrary.allFoods {
            #expect(!food.emoji.isEmpty, "\(food.name) 缺少 emoji")
        }
    }

    @Test("Watch 快选列表有 8 种食物")
    func watchQuickPickCount() {
        #expect(PresetFoodLibrary.watchQuickPicks.count == 8)
    }

    @Test("搜索功能: 搜'奶茶'能找到")
    func searchMilkTea() {
        let results = PresetFoodLibrary.search("奶茶")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.name.contains("奶茶") })
    }

    @Test("搜索功能: 空字符串返回全部")
    func searchEmpty() {
        let results = PresetFoodLibrary.search("")
        #expect(results.count == PresetFoodLibrary.allFoods.count)
    }

    @Test("搜索功能: 不存在的食物返回空")
    func searchNotFound() {
        let results = PresetFoodLibrary.search("火星蛋糕")
        #expect(results.isEmpty)
    }
}
