import Foundation

/// 励志文案系统 — 按进度阶段分组, 支持变量替换
///
/// 变量: {{food}} = 食物名, {{progress}} = 进度百分比, {{remaining}} = 剩余 kcal
public enum MotivationalQuotes {

    /// 进度阶段
    public enum Stage: CaseIterable, Sendable {
        case start      // 0-25%
        case middle     // 25-75%
        case sprint     // 75-99%
        case complete   // 100%
    }

    /// 根据进度百分比获取阶段
    public static func stage(for progress: Int) -> Stage {
        switch progress {
        case ..<25:     return .start
        case 25..<75:   return .middle
        case 75..<100:  return .sprint
        default:        return .complete
        }
    }

    /// 获取指定阶段的随机文案 (排除已展示的)
    public static func randomQuote(
        for stage: Stage,
        excluding shown: Set<Int> = []
    ) -> (index: Int, template: String)? {
        let pool = quotes[stage] ?? []
        let available = pool.enumerated().filter { !shown.contains($0.offset) }
        guard let pick = available.randomElement() else { return nil }
        return (index: pick.offset, template: pick.element)
    }

    /// 替换文案中的变量
    public static func render(
        template: String,
        food: String,
        progress: Int,
        remaining: Int
    ) -> String {
        template
            .replacingOccurrences(of: "{{food}}", with: food)
            .replacingOccurrences(of: "{{progress}}", with: "\(progress)")
            .replacingOccurrences(of: "{{remaining}}", with: "\(remaining)")
    }

    // MARK: - 文案库 (50 条)

    public static let quotes: [Stage: [String]] = [
        .start: [
            "出发了，{{food}}的账慢慢还",
            "第一步最难，但你已经迈出来了",
            "这口{{food}}开始紧张了",
            "开始磨平，{{food}}等着被消灭",
            "动起来了，每一步都在还债",
            "今天的你选择了不赖账",
            "{{food}}以为你不会来，证明它错了",
            "才刚开始，别急，慢慢来",
            "一步一步，{{food}}正在缩小",
            "你已经比沙发上的自己强了",
            "起步价已付，继续前进",
            "身体在动，{{food}}在抖",
        ],
        .middle: [
            "已经{{progress}}%了，比大多数人强",
            "还剩{{remaining}} kcal，不算多了",
            "{{food}}正在被你慢慢磨平",
            "这个速度，{{food}}扛不住了",
            "再坚持一会，你比昨天的自己强",
            "一半都过了，还怕什么",
            "{{food}}的账快还完一半了",
            "继续保持，节奏很棒",
            "{{remaining}} kcal，就这点了",
            "你正在把{{food}}变成汗水",
            "进度过半，{{food}}已经慌了",
            "每消耗一卡，都是对自己的投资",
            "保持节奏，你是磨平高手",
            "{{progress}}%了，胜利在望",
            "这不比刷手机有意义？",
            "{{food}}求你放过它了",
        ],
        .sprint: [
            "最后冲刺！{{food}}快被磨平了",
            "别在这里放弃，还剩一点点",
            "就差{{remaining}} kcal，结清就在眼前",
            "{{progress}}%！冲刺！",
            "终点就在前面，别停下来",
            "最后一口气，{{food}}撑不住了",
            "马上就能结清了，加油！",
            "{{remaining}} kcal，最后的倔强",
            "离结清只差一点点了",
            "{{food}}的最后挣扎，别心软",
            "快了快了，坚持住！",
            "最后{{remaining}} kcal，拼了！",
        ],
        .complete: [
            "结清！这口没有赖账",
            "磨平了！你是自律的人",
            "干得漂亮，{{food}}的账清了",
            "完美结清，今天赢了",
            "{{food}}被你彻底磨平了",
            "自律给你自由，今天又证明了一次",
            "结清！给自己一个大拇指",
            "这单结清了，你是狠人",
            "磨平完毕，无债一身轻",
            "{{food}}已成为历史，你是冠军",
        ],
    ]
}
