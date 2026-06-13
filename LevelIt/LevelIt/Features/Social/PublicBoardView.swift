import SwiftUI
import SwiftData
import LevelItShared

/// 发榜广场：浏览公开挑战并认领。
struct PublicBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var localChallenges: [PKChallenge]

    @State private var items: [SocialService.BoardChallenge] = []
    @State private var loading = false
    @State private var claimingId: String?
    @State private var errorText: String?
    @State private var showError = false

    private var profile: UserProfile {
        UserProfileStore.current ?? UserProfile(
            gender: .male, age: AppConstants.ProfileDefaults.defaultAge,
            heightCM: AppConstants.ProfileDefaults.defaultHeightCM,
            weightKG: AppConstants.ProfileDefaults.defaultWeightKG, activityLevel: .light
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DS.Spacing.md) {
                if items.isEmpty && !loading {
                    emptyState
                }
                ForEach(items) { item in
                    boardRow(item)
                }
            }
            .padding()
        }
        .navigationTitle("发榜广场")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if loading && items.isEmpty { ProgressView() } }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("提示", isPresented: $showError) {
            Button("好的", role: .cancel) {}
        } message: { Text(errorText ?? "出错了") }
    }

    private func boardRow(_ item: SocialService.BoardChallenge) -> some View {
        let alreadyClaimed = localChallenges.contains { $0.serverId == item.id }
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Image(systemName: typeIcon(item.type)).foregroundStyle(DS.Colors.accent)
                Text(item.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(targetText(item)).font(.caption.weight(.medium)).foregroundStyle(DS.Colors.accent)
            }
            HStack {
                Text("来自 \(item.challengerName)").font(.caption).foregroundStyle(.secondary)
                if let u = item.challengerUsername {
                    Text("@\(u)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if item.isMine {
                    Text("我发布的")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                } else {
                    Button {
                        Task { await claim(item) }
                    } label: {
                        if claimingId == item.id { ProgressView().controlSize(.small) }
                        else { Text(alreadyClaimed ? "已认领" : "认领").font(.caption.weight(.semibold)) }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(alreadyClaimed || claimingId != nil)
                }
            }
            if let note = item.note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding().background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("广场暂时没有公开挑战").font(.headline)
            Text("去 PK 中心发起一个公开挑战，让大家来认领。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.xl * 2)
    }

    // MARK: - 逻辑

    private func reload() async {
        loading = true; defer { loading = false }
        do { items = try await SocialService.board() }
        catch { surface(error) }
    }

    @MainActor
    private func claim(_ item: SocialService.BoardChallenge) async {
        claimingId = item.id; defer { claimingId = nil }
        do {
            let challenge = try await PKSyncService.claimChallenge(
                inviteCode: item.inviteCode,
                opponentName: profile.displayName,
                opponentCode: profile.inviteCode
            )
            modelContext.insert(challenge)
            try? modelContext.save()
            await reload()
        } catch { surface(error) }
    }

    private func surface(_ error: Error) {
        errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showError = true
    }

    private func typeIcon(_ raw: String) -> String {
        PKChallengeType(rawValue: raw)?.iconName ?? "flame.fill"
    }
    private func targetText(_ item: SocialService.BoardChallenge) -> String {
        PKChallengeType(rawValue: item.type) == .streakSprint
            ? "\(item.durationDays) 天" : "\(item.targetCalories) kcal"
    }
}
