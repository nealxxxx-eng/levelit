import LevelItShared

/// 云端备份存根 — 当前使用 UserDefaults 本地存储
/// 升级到付费 Apple Developer 账号后可启用 CloudKit 实现
enum CloudKitService {

    static func save(_ profile: UserProfile) async throws {
        // CloudKit 需要付费开发者账号，当前仅本地存储
        // UserProfileStore.save() 已在调用方完成
    }

    static func fetch() async throws -> UserProfile? {
        // 无云端数据，返回 nil
        return nil
    }

    static func checkAccountStatus() async -> Bool {
        return false
    }
}
