import Foundation

/// 预置食物库 — 30-50 种常见食物
public enum PresetFoodLibrary {

    /// 全部食物
    public static let allFoods: [PresetFood] = {
        var foods: [PresetFood] = []
        foods.append(contentsOf: milkTea)
        foods.append(contentsOf: snacks)
        foods.append(contentsOf: fastFood)
        foods.append(contentsOf: drinks)
        foods.append(contentsOf: desserts)
        foods.append(contentsOf: coffees)
        return foods
    }()

    /// 按分类获取食物
    public static func foods(for category: FoodCategory) -> [PresetFood] {
        allFoods.filter { $0.category == category }
    }

    /// 搜索食物 (名称模糊匹配)
    public static func search(_ query: String) -> [PresetFood] {
        guard !query.isEmpty else { return allFoods }
        let lowered = query.lowercased()
        return allFoods.filter { $0.name.lowercased().contains(lowered) }
    }

    /// Watch 快选食物 (高频 Top 8)
    public static let watchQuickPicks: [PresetFood] = [
        make("黑糖珍珠奶茶", "🧋", .milkTea, 340),
        make("拿铁", "☕", .coffee, 180),
        make("薯片", "🥔", .snack, 280),
        make("可乐", "🥤", .drink, 140),
        make("炸鸡", "🍗", .fastFood, 350),
        make("甜甜圈", "🍩", .dessert, 260),
        make("汉堡", "🍔", .fastFood, 450),
        make("冰淇淋", "🍦", .dessert, 200),
    ]

    // MARK: - 奶茶类

    public static let milkTea: [PresetFood] = [
        make("黑糖珍珠奶茶", "🧋", .milkTea, 340),
        make("抹茶拿铁", "🍵", .milkTea, 250),
        make("芋泥波波", "🧋", .milkTea, 380),
        make("柠檬茶", "🍋", .milkTea, 120),
        make("杨枝甘露", "🥭", .milkTea, 300),
        make("椰椰奶冻", "🥥", .milkTea, 280),
        make("多肉葡萄", "🍇", .milkTea, 260),
        make("草莓奶昔", "🍓", .milkTea, 320),
    ]

    // MARK: - 零食类

    public static let snacks: [PresetFood] = [
        make("海盐薯片", "🥔", .snack, 280),
        make("巧克力", "🍫", .snack, 230),
        make("坚果混合", "🥜", .snack, 180),
        make("饼干", "🍪", .snack, 150),
        make("辣条", "🌶️", .snack, 200),
        make("蛋黄酥", "🥮", .snack, 250),
        make("肉松小贝", "🧁", .snack, 220),
        make("瓜子", "🌻", .snack, 160),
    ]

    // MARK: - 快餐类

    public static let fastFood: [PresetFood] = [
        make("炸鸡", "🍗", .fastFood, 350),
        make("薯条(中)", "🍟", .fastFood, 320),
        make("汉堡", "🍔", .fastFood, 450),
        make("披萨(一片)", "🍕", .fastFood, 280),
        make("烤串(5串)", "🍢", .fastFood, 400),
        make("煎饺(10个)", "🥟", .fastFood, 350),
        make("炸鸡排", "🍖", .fastFood, 420),
        make("热狗", "🌭", .fastFood, 290),
    ]

    // MARK: - 饮料类

    public static let drinks: [PresetFood] = [
        make("可乐", "🥤", .drink, 140),
        make("橙汁", "🧃", .drink, 110),
        make("啤酒", "🍺", .drink, 150),
        make("气泡水(含糖)", "🫧", .drink, 80),
        make("酸奶", "🥛", .drink, 120),
        make("运动饮料", "🧴", .drink, 100),
    ]

    // MARK: - 甜品类

    public static let desserts: [PresetFood] = [
        make("糖霜甜甜圈", "🍩", .dessert, 260),
        make("芝士蛋糕", "🍰", .dessert, 310),
        make("冰淇淋", "🍦", .dessert, 200),
        make("提拉米苏", "🧁", .dessert, 290),
        make("马卡龙(3个)", "🍬", .dessert, 180),
        make("布丁", "🍮", .dessert, 160),
        make("泡芙", "🥐", .dessert, 220),
        make("华夫饼", "🧇", .dessert, 350),
    ]

    // MARK: - 咖啡类

    public static let coffees: [PresetFood] = [
        make("拿铁", "☕", .coffee, 180),
        make("摩卡", "☕", .coffee, 250),
        make("美式", "☕", .coffee, 15),
        make("星冰乐", "🧊", .coffee, 350),
        make("卡布奇诺", "☕", .coffee, 120),
        make("焦糖玛奇朵", "☕", .coffee, 240),
    ]

    // MARK: - Private

    private static func make(_ name: String, _ emoji: String, _ category: FoodCategory, _ kcal: Int) -> PresetFood {
        PresetFood(
            id: "\(category.rawValue)_\(name)",
            name: name,
            emoji: emoji,
            category: category,
            estimatedCalories: kcal
        )
    }
}
