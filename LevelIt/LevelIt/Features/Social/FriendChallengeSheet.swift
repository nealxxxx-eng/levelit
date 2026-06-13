import SwiftUI
import SwiftData
import LevelItShared

/// 向某位好友直接发起 PK 挑战（定向挑战，对方在 PK 中心接受）。
struct FriendChallengeSheet: View {
    let target: SocialService.UserSummary
    let profile: UserProfile
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var challengeType: PKChallengeType = .burnTarget
    @State private var targetCalories: Double = 300
    @State private var durationDays: Double = 3
    @State private var creating = false
    @State private var errorText: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("对手") {
                    HStack {
                        Text(target.displayName)
                        Spacer()
                        Text("@\(target.username)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Section("挑战类型") {
                    Picker("类型", selection: $challengeType) {
                        ForEach(PKChallengeType.allCases, id: \.self) { t in
                            Label(t.displayName, systemImage: t.iconName).tag(t)
                        }
                    }
                }
                if challengeType == .streakSprint {
                    Section("目标天数") {
                        Stepper("\(Int(durationDays)) 天", value: $durationDays, in: 1...14)
                    }
                } else {
                    Section("目标消耗") {
                        VStack(alignment: .leading) {
                            Text("\(Int(targetCalories)) kcal").font(.headline).foregroundStyle(DS.Colors.accent)
                            Slider(value: $targetCalories, in: 50...1200, step: 10).tint(DS.Colors.accent)
                        }
                    }
                }
            }
            .navigationTitle("挑战好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发起") { Task { await create() } }
                        .fontWeight(.semibold).disabled(creating)
                }
            }
            .alert("发起失败", isPresented: $showError) {
                Button("好的", role: .cancel) {}
            } message: { Text(errorText ?? "出错了") }
        }
    }

    @MainActor
    private func create() async {
        creating = true; defer { creating = false }
        let title = challengeType == .streakSprint
            ? "\(Int(durationDays)) 天连续磨平"
            : "燃烧 \(Int(targetCalories)) kcal"
        let challenge = PKChallenge(
            type: challengeType,
            title: title,
            challengerName: profile.displayName,
            challengerCode: profile.inviteCode,
            opponentName: target.displayName,
            targetCalories: challengeType == .streakSprint ? 1 : Int(targetCalories),
            durationDays: Int(durationDays)
        )
        do {
            let result = try await PKSyncService.createChallenge(challenge, opponentUsername: target.username)
            challenge.serverId = result.serverId
            challenge.serverInviteCode = result.inviteCode
            modelContext.insert(challenge)
            try? modelContext.save()
            dismiss()
            onDone()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "网络异常"
            showError = true
        }
    }
}
