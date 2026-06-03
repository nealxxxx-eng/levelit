import Testing
import Foundation
@testable import LevelItShared

@Suite("MotivationalQuotes Tests")
struct MotivationalQuotesTests {

    // MARK: - 阶段映射

    @Test("进度阶段正确映射")
    func stageMapping() {
        #expect(MotivationalQuotes.stage(for: 0) == .start)
        #expect(MotivationalQuotes.stage(for: 24) == .start)
        #expect(MotivationalQuotes.stage(for: 25) == .middle)
        #expect(MotivationalQuotes.stage(for: 74) == .middle)
        #expect(MotivationalQuotes.stage(for: 75) == .sprint)
        #expect(MotivationalQuotes.stage(for: 99) == .sprint)
        #expect(MotivationalQuotes.stage(for: 100) == .complete)
        #expect(MotivationalQuotes.stage(for: 150) == .complete)
    }

    // MARK: - 文案库完整性

    @Test("每个阶段至少有 8 条文案")
    func minimumQuotesPerStage() {
        for stage in MotivationalQuotes.Stage.allCases {
            let quotes = MotivationalQuotes.quotes[stage] ?? []
            #expect(quotes.count >= 8,
                    "\(stage) 阶段文案不足 8 条, 实际 \(quotes.count) 条")
        }
    }

    @Test("总文案数至少 50 条")
    func totalQuoteCount() {
        let total = MotivationalQuotes.quotes.values.reduce(0) { $0 + $1.count }
        #expect(total >= 50, "总文案数 \(total) 不足 50 条")
    }

    @Test("所有文案非空")
    func nonEmptyQuotes() {
        for (stage, quotes) in MotivationalQuotes.quotes {
            for (i, quote) in quotes.enumerated() {
                #expect(!quote.isEmpty, "\(stage) 第 \(i) 条文案为空")
            }
        }
    }

    // MARK: - 变量替换

    @Test("变量替换正确")
    func variableReplacement() {
        let result = MotivationalQuotes.render(
            template: "已经{{progress}}%了，{{food}}还剩{{remaining}} kcal",
            food: "奶茶",
            progress: 50,
            remaining: 170
        )
        #expect(result == "已经50%了，奶茶还剩170 kcal")
    }

    @Test("无变量的文案保持不变")
    func noVariables() {
        let template = "第一步最难，但你已经迈出来了"
        let result = MotivationalQuotes.render(
            template: template,
            food: "奶茶",
            progress: 10,
            remaining: 270
        )
        #expect(result == template)
    }

    // MARK: - 不重复选取

    @Test("排除已展示文案后能获取新文案")
    func excludeShownQuotes() {
        let stage = MotivationalQuotes.Stage.start
        var shown = Set<Int>()

        for _ in 0..<5 {
            guard let pick = MotivationalQuotes.randomQuote(for: stage, excluding: shown) else {
                break
            }
            #expect(!shown.contains(pick.index), "不应重复选取已展示的文案")
            shown.insert(pick.index)
        }

        #expect(shown.count == 5)
    }

    @Test("全部展示完后返回 nil")
    func exhaustedReturnsNil() {
        let stage = MotivationalQuotes.Stage.complete
        let count = MotivationalQuotes.quotes[stage]?.count ?? 0
        let allShown = Set(0..<count)

        let result = MotivationalQuotes.randomQuote(for: stage, excluding: allShown)
        #expect(result == nil)
    }
}
