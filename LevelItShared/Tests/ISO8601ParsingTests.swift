import Testing
import Foundation
@testable import LevelItShared

@Suite("ISO8601 容错解析")
struct ISO8601ParsingTests {

    /// 构造一个 UTC 时刻，避免手算 Unix 时间戳出错。
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    // MARK: - 回归：后端 toISOString() 带毫秒，曾导致解析为 nil

    @Test("带毫秒（后端 new Date().toISOString() 真实格式）能解析")
    func parsesFractionalSeconds() {
        let date = ISO8601.date(from: "2026-06-17T10:30:00.000Z")
        #expect(date == utc(2026, 6, 17, 10, 30, 0))
    }

    @Test("不带毫秒的标准 ISO8601 仍能解析")
    func parsesPlainSeconds() {
        let date = ISO8601.date(from: "2026-06-17T10:30:00Z")
        #expect(date == utc(2026, 6, 17, 10, 30, 0))
    }

    @Test("带毫秒与不带毫秒解析出同一时刻")
    func fractionalAndPlainAgree() {
        let withMs = ISO8601.date(from: "2026-06-17T10:30:00.000Z")
        let noMs   = ISO8601.date(from: "2026-06-17T10:30:00Z")
        #expect(withMs == noMs)
        #expect(withMs != nil)
    }

    @Test("空串 / 乱码返回 nil，不崩溃")
    func invalidReturnsNil() {
        #expect(ISO8601.date(from: "") == nil)
        #expect(ISO8601.date(from: "not-a-date") == nil)
        #expect(ISO8601.date(from: "2026/06/17 10:30") == nil)
    }

    // MARK: - 往返：输出带毫秒并能被自身解析

    @Test("string(from:) 输出可被 date(from:) 还原（往返无损到秒）")
    func roundTrip() {
        let original = utc(2026, 6, 17, 10, 30, 0)
        let encoded = ISO8601.string(from: original)
        let decoded = ISO8601.date(from: encoded)
        #expect(decoded == original)
    }
}
