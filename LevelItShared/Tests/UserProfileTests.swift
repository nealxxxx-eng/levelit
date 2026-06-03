import Testing
import Foundation
@testable import LevelItShared

@Suite("UserProfile Tests")
struct UserProfileTests {

    @Test("AI 估算值优先作为 TDEE 默认基准")
    func aiEstimateOverridesFormulaTDEE() {
        let profile = UserProfile(
            gender: .male,
            age: 30,
            heightCM: 170,
            weightKG: 65,
            activityLevel: .light,
            aiEstimatedTDEE: 2450,
            aiEstimateSummary: "基于轻度活动估算",
            aiEstimateUpdatedAt: Date()
        )

        #expect(profile.formulaTDEE != 2450)
        #expect(profile.tdee == 2450)
    }

    @Test("旧版档案 JSON 缺少 AI 字段时仍可解码")
    func legacyProfileDecodesWithoutAIEstimate() throws {
        let json = """
        {
          "gender": "female",
          "age": 28,
          "heightCM": 165,
          "weightKG": 55.5,
          "activityLevel": "moderate",
          "createdAt": "2026-05-17T00:00:00Z",
          "updatedAt": "2026-05-17T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(UserProfile.self, from: json)

        #expect(profile.aiEstimatedTDEE == nil)
        #expect(profile.tdee == profile.formulaTDEE)
    }

    @Test("异常 AI 估算值不会污染 TDEE")
    func invalidAIEstimateFallsBackToFormulaTDEE() {
        let profile = UserProfile(
            gender: .male,
            age: 30,
            heightCM: 170,
            weightKG: 65,
            activityLevel: .light,
            aiEstimatedTDEE: 20000
        )

        #expect(profile.tdee == profile.formulaTDEE)
    }
}
