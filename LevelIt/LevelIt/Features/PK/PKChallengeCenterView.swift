import SwiftUI
import SwiftData
import LevelItShared

struct PKChallengeCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PKChallenge.createdAt, order: .reverse) private var challenges: [PKChallenge]
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]

    // 发起挑战表单
    @State private var challengeType: PKChallengeType = .firstToSettle
    @State private var opponentName = ""
    @State private var targetCalories: Double = 300
    @State private var durationDays: Double = 3
    @State private var latestInvite: PKChallenge?

    // 待接受管理
    @State private var editingChallenge: PKChallenge?
    @State private var withdrawTarget: PKChallenge?

    // 认领挑战
    @State private var showClaimSheet = false
    @State private var claimCode = ""
    @State private var claimChallengerName = ""
    @State private var claimType: PKChallengeType = .firstToSettle
    @State private var claimTargetCalories: Double = 300
    @State private var claimDuration: Double = 1

    private var profile: UserProfile {
        UserProfileStore.current ?? UserProfile(
            gender: .male,
            age: AppConstants.ProfileDefaults.defaultAge,
            heightCM: AppConstants.ProfileDefaults.defaultHeightCM,
            weightKG: AppConstants.ProfileDefaults.defaultWeightKG,
            activityLevel: .light
        )
    }

    private var todayPendingKcal: Int {
        allTasks.filter { $0.isPendingForDay() }.reduce(0) { $0 + max(0, $1.targetBurnCalories - $1.burnedCalories) }
    }

    private var activeChallenges: [PKChallenge] {
        challenges.filter { $0.status == .invited || $0.status == .accepted }
    }

    private var historyChallenges: [PKChallenge] {
        challenges.filter { $0.status.isTerminal }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                accountCard
                createCard
                claimCard

                if let latestInvite {
                    inviteCard(latestInvite)
                }

                if !activeChallenges.isEmpty {
                    challengeSection(title: "进行中", items: activeChallenges)
                }

                if !historyChallenges.isEmpty {
                    challengeSection(title: "历史记录", items: historyChallenges)
                }

                if challenges.isEmpty {
                    emptyState
                }
            }
            .padding()
        }
        .navigationTitle("朋友 PK")
        .navigationBarTitleDisplayMode(.inline)
        .task { checkExpiredChallenges() }
        .onAppear {
            if todayPendingKcal > 0 { targetCalories = Double(todayPendingKcal) }
        }
        .sheet(item: $editingChallenge) { challenge in
            PKChallengeEditView(challenge: challenge) { updated in
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showClaimSheet) {
            claimSheet
        }
        .alert("撤回挑战", isPresented: .constant(withdrawTarget != nil), presenting: withdrawTarget) { challenge in
            Button("确认撤回", role: .destructive) {
                challenge.status = .cancelled
                try? modelContext.save()
                withdrawTarget = nil
                if latestInvite?.id == challenge.id { latestInvite = nil }
            }
            Button("取消", role: .cancel) { withdrawTarget = nil }
        } message: { challenge in
            Text("撤回后对手将无法通过邀请码认领「\(challenge.title)」。")
        }
    }

    // MARK: - 账号卡片

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName)
                        .font(.headline)
                    Text("邀请码 \(profile.inviteCode)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundStyle(DS.Colors.accent)
            }

            HStack(spacing: 0) {
                metric(value: "\(activeChallenges.count)", label: "进行中")
                Divider().frame(height: 32)
                metric(value: "\(challenges.filter { $0.status == .completed }.count)", label: "已完成")
                Divider().frame(height: 32)
                metric(value: "\(todayPendingKcal)", label: "今日待磨")
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 发起挑战

    private var createCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("发起挑战")
                .font(.headline)

            Picker("挑战类型", selection: $challengeType) {
                ForEach(PKChallengeType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.iconName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            TextField("对手昵称（可选）", text: $opponentName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)

            if challengeType == .streakSprint {
                sliderRow(title: "连续天数", value: $durationDays, range: 1...14, step: 1, display: "\(Int(durationDays)) 天")
            } else {
                sliderRow(title: "目标消耗", value: $targetCalories, range: 50...1200, step: 10, display: "\(Int(targetCalories)) kcal")
            }

            Button { createInvite() } label: {
                Label("生成邀请", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DS.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 认领挑战入口

    private var claimCard: some View {
        Button { showClaimSheet = true } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title2)
                    .foregroundStyle(DS.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("认领挑战")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("输入朋友的邀请码，参与他们发起的挑战")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 邀请卡片（刚生成后展示）

    private func inviteCard(_ challenge: PKChallenge) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("邀请已生成")
                    .font(.headline)
                Spacer()
                Text(challenge.shareCode)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(DS.Colors.accent)
            }

            Text(challenge.inviteText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: DS.Spacing.sm) {
                ShareLink(item: challenge.inviteText) {
                    Label("分享给朋友", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.14))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }

                Button {
                    latestInvite = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.medium))
                        .padding(10)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 挑战列表分区

    private func challengeSection(title: String, items: [PKChallenge]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, challenge in
                    if index > 0 {
                        Divider().padding(.leading, 56)
                    }
                    challengeRow(challenge)
                }
            }
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
    }

    // MARK: - 挑战行

    private func challengeRow(_ challenge: PKChallenge) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: challenge.type.iconName)
                    .font(.title3)
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(challenge.title)
                            .font(.subheadline.weight(.medium))
                        if !challenge.isChallenger {
                            Text("认领")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(DS.Colors.accent.opacity(0.12))
                                .foregroundStyle(DS.Colors.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text(challengeSubtitle(challenge))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(challenge.status)
            }

            // 进行中：显示进度条
            if challenge.status == .accepted {
                let progress = liveProgress(for: challenge)
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DS.Colors.accent)
                                .frame(width: geo.size.width * progress)
                                .animation(.easeOut, value: progress)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("\(Int(progress * 100))% 完成")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if challenge.type != .streakSprint {
                            let burned = Int(progress * Double(challenge.targetCalories))
                            Text("\(burned) / \(challenge.targetCalories) kcal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 46)
            }

            // 待认领：显示过期倒计时
            if challenge.status == .invited && challenge.isChallenger {
                HStack {
                    Spacer()
                    let h = challenge.hoursUntilExpiry
                    Label(h > 0 ? "\(h) 小时后过期" : "即将过期", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(h < 6 ? .orange : .secondary)
                }
                .padding(.leading, 46)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, DS.Spacing.sm)
        .contextMenu { contextMenuItems(for: challenge) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            trailingSwipeActions(for: challenge)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            leadingSwipeActions(for: challenge)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for challenge: PKChallenge) -> some View {
        if challenge.status == .invited && challenge.isChallenger {
            Button { editingChallenge = challenge } label: {
                Label("编辑挑战", systemImage: "pencil")
            }
            ShareLink(item: challenge.inviteText) {
                Label("重新分享", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) { withdrawTarget = challenge } label: {
                Label("撤回邀请", systemImage: "arrow.uturn.backward")
            }
        }

        if challenge.status == .accepted {
            Button(role: .destructive) {
                challenge.status = .cancelled
                try? modelContext.save()
            } label: {
                Label("认输放弃", systemImage: "flag.slash")
            }
        }

        if challenge.status.isTerminal {
            Button(role: .destructive) {
                modelContext.delete(challenge)
                try? modelContext.save()
            } label: {
                Label("删除记录", systemImage: "trash")
            }
        }
    }

    // MARK: - Swipe Actions

    @ViewBuilder
    private func trailingSwipeActions(for challenge: PKChallenge) -> some View {
        if challenge.status == .invited && challenge.isChallenger {
            Button(role: .destructive) { withdrawTarget = challenge } label: {
                Label("撤回", systemImage: "arrow.uturn.backward")
            }
        }
        if challenge.status.isTerminal {
            Button(role: .destructive) {
                modelContext.delete(challenge)
                try? modelContext.save()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func leadingSwipeActions(for challenge: PKChallenge) -> some View {
        if challenge.status == .invited && challenge.isChallenger {
            Button { editingChallenge = challenge } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(DS.Colors.accent)

            ShareLink(item: challenge.inviteText) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            .tint(.green)
        }
    }

    // MARK: - 认领 Sheet

    private var claimSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("邀请码（如 ABCD-XYZ123）", text: $claimCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("对方昵称（可选）", text: $claimChallengerName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("邀请信息")
                } footer: {
                    Text("邀请码可在朋友分享的消息里找到，格式为 XXXX-YYYYYY。")
                }

                Section("挑战类型") {
                    Picker("类型", selection: $claimType) {
                        ForEach(PKChallengeType.allCases, id: \.self) { t in
                            Label(t.displayName, systemImage: t.iconName).tag(t)
                        }
                    }
                }

                if claimType == .streakSprint {
                    Section("目标天数") {
                        sliderRow(title: "天数", value: $claimDuration, range: 1...14, step: 1, display: "\(Int(claimDuration)) 天")
                    }
                } else {
                    Section("目标消耗") {
                        sliderRow(title: "目标", value: $claimTargetCalories, range: 50...1200, step: 10, display: "\(Int(claimTargetCalories)) kcal")
                    }
                }
            }
            .navigationTitle("认领挑战")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showClaimSheet = false
                        resetClaimForm()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("认领") { claimChallenge() }
                        .fontWeight(.semibold)
                        .disabled(claimCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("还没有挑战")
                .font(.headline)
            Text("生成邀请发给朋友，或输入邀请码认领朋友的挑战。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, DS.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 通用子视图

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusBadge(_ status: PKChallengeStatus) -> some View {
        Text(status.displayName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.14))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Colors.accent)
            }
            Slider(value: value, in: range, step: step).tint(DS.Colors.accent)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - 业务逻辑

    private func createInvite() {
        let opponent = opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        switch challengeType {
        case .firstToSettle:  title = todayPendingKcal > 0 ? "今日待磨平先结清" : "先结清挑战"
        case .burnTarget:     title = "燃烧 \(Int(targetCalories)) kcal"
        case .streakSprint:   title = "\(Int(durationDays)) 天连续磨平"
        }

        let challenge = PKChallenge(
            type: challengeType,
            title: title,
            challengerName: profile.displayName,
            challengerCode: profile.inviteCode,
            opponentName: opponent.isEmpty ? nil : opponent,
            targetCalories: challengeType == .streakSprint ? max(1, todayPendingKcal) : Int(targetCalories),
            durationDays: Int(durationDays),
            linkedTaskId: allTasks.first(where: { $0.isPendingForDay() })?.id
        )
        modelContext.insert(challenge)
        try? modelContext.save()
        latestInvite = challenge
        opponentName = ""
    }

    private func claimChallenge() {
        let code = claimCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }

        let challenger = claimChallengerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = claimType == .streakSprint
            ? "\(Int(claimDuration)) 天连续磨平"
            : "燃烧 \(Int(claimTargetCalories)) kcal"

        let challenge = PKChallenge(
            type: claimType,
            title: title,
            challengerName: challenger.isEmpty ? "对手" : challenger,
            challengerCode: code,
            opponentName: profile.displayName,
            targetCalories: Int(claimTargetCalories),
            durationDays: Int(claimDuration),
            status: .accepted,
            isChallenger: false
        )
        modelContext.insert(challenge)
        try? modelContext.save()
        showClaimSheet = false
        resetClaimForm()
    }

    private func resetClaimForm() {
        claimCode = ""
        claimChallengerName = ""
        claimType = .firstToSettle
        claimTargetCalories = 300
        claimDuration = 1
    }

    /// 把自然过期的 invited 挑战标记为 expired
    private func checkExpiredChallenges() {
        var changed = false
        for challenge in challenges where challenge.isNaturallyExpired {
            challenge.status = .expired
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    /// 实时计算进度：优先从关联任务读取，其次用存储值
    private func liveProgress(for challenge: PKChallenge) -> Double {
        if let taskId = challenge.linkedTaskId,
           let task = allTasks.first(where: { $0.id == taskId }),
           challenge.targetCalories > 0 {
            return min(1.0, Double(task.burnedCalories) / Double(challenge.targetCalories))
        }
        return challenge.progressRatio
    }

    // MARK: - 样式辅助

    private func challengeSubtitle(_ challenge: PKChallenge) -> String {
        let target = challenge.type == .streakSprint
            ? "\(challenge.durationDays) 天"
            : "\(challenge.targetCalories) kcal"
        let name = challenge.isChallenger
            ? (challenge.opponentName.map { "vs \($0)" } ?? "")
            : "来自 \(challenge.challengerName)"
        let parts = [name, target, challenge.createdAt.formatted(date: .abbreviated, time: .omitted)]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func statusColor(_ status: PKChallengeStatus) -> Color {
        switch status {
        case .draft:     return .secondary
        case .invited:   return DS.Colors.accent
        case .accepted:  return .orange
        case .completed: return .green
        case .cancelled: return .secondary
        case .expired:   return .secondary
        case .rejected:  return .red
        }
    }
}
