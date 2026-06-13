import SwiftUI
import LevelItShared

/// 排行榜：按 PK 胜场（其次累计消耗）排名。
struct LeaderboardView: View {
    @State private var rows: [SocialService.LeaderboardRow] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showError = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if rows.isEmpty && !loading {
                    emptyState
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Divider().padding(.leading, 56) }
                    rowView(row)
                }
            }
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .padding()
        }
        .navigationTitle("排行榜")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if loading && rows.isEmpty { ProgressView() } }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("提示", isPresented: $showError) {
            Button("好的", role: .cancel) {}
        } message: { Text(errorText ?? "出错了") }
    }

    private func rowView(_ row: SocialService.LeaderboardRow) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Text("\(row.rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(medalColor(row.rank))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName).font(.subheadline.weight(.medium))
                Text("@\(row.username)").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.wins) 胜").font(.subheadline.weight(.semibold)).foregroundStyle(DS.Colors.accent)
                Text("\(row.burned) kcal").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(row.isMe ? DS.Colors.accent.opacity(0.08) : Color.clear)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "trophy").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("还没有排名数据").font(.headline)
            Text("完成 PK 挑战即可上榜。").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.xl * 2)
    }

    private func reload() async {
        loading = true; defer { loading = false }
        do { rows = try await SocialService.leaderboard() }
        catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showError = true
        }
    }

    private func medalColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .secondary
        }
    }
}
