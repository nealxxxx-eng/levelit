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
    @State private var claimMyName = ""

    // 同步状态
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var showSyncError = false

    // 发布到广场（公开挑战）
    @State private var postToBoard = false

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
                socialNavRow
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
        .toolbar {
            if isSyncing {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProgressView().scaleEffect(0.75)
                }
            }
        }
        .task {
            checkExpiredChallenges()
            await runSync()
        }
        .refreshable {
            await runSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pkDeviceTokenUpdated)) { notification in
            guard let token = notification.object as? String else { return }
            Task { await registerDeviceTokenForActive(token) }
        }
        .onAppear {
            claimMyName = profile.displayName
            if todayPendingKcal > 0 { targetCalories = Double(todayPendingKcal) }
        }
        .sheet(item: $editingChallenge) { challenge in
            PKChallengeEditView(challenge: challenge) { updated in
                try? modelContext.save()
                Task { try? await PKSyncService.updateChallenge(updated) }
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
                Task { try? await PKSyncService.cancelChallenge(challenge) }
            }
            Button("取消", role: .cancel) { withdrawTarget = nil }
        } message: { challenge in
            Text("撤回后对手将无法通过邀请码认领「\(challenge.title)」。")
        }
        .alert("同步失败", isPresented: $showSyncError) {
            Button("好的", role: .cancel) { }
        } message: {
            Text(syncError ?? "未知错误")
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

    // MARK: - 社交入口

    private var socialNavRow: some View {
        HStack(spacing: DS.Spacing.md) {
            navTile(title: "好友", icon: "person.2.fill", route: .friends)
            navTile(title: "广场", icon: "rectangle.stack.fill", route: .pkBoard)
            navTile(title: "排行榜", icon: "trophy.fill", route: .leaderboard)
        }
    }

    private func navTile(title: String, icon: String, route: AppRoute) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(DS.Colors.accent)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.md)
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(.plain)
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

            Toggle(isOn: $postToBoard) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("发布到广场").font(.subheadline.weight(.medium))
                    Text("任何人都能在广场看到并认领").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(DS.Colors.accent)

            Button { Task { await createInvite() } } label: {
                Label(isSyncing ? "生成中…" : (postToBoard ? "发布到广场" : "生成邀请"), systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DS.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
            .disabled(isSyncing)
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
                Text(challenge.effectiveInviteCode)
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

                if hasActions(for: challenge) {
                    Menu {
                        contextMenuItems(for: challenge)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                }
            }

            // 进行中：显示进度条（我方 + 对手）
            if challenge.status == .accepted {
                let myPct  = liveProgress(for: challenge)
                let oppPct = challenge.opponentProgressRatio
                VStack(spacing: 6) {
                    // 我方
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.15))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(DS.Colors.accent)
                                    .frame(width: geo.size.width * myPct)
                                    .animation(.easeOut, value: myPct)
                            }
                        }
                        .frame(height: 6)
                        HStack {
                            Text("我 \(Int(myPct * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if challenge.type != .streakSprint {
                                Text("\(Int(myPct * Double(challenge.targetCalories))) / \(challenge.targetCalories) kcal")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // 对手（serverId 存在才显示，否则无服务端数据）
                    if challenge.serverId != nil {
                        VStack(spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.secondary.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.orange)
                                        .frame(width: geo.size.width * oppPct)
                                        .animation(.easeOut, value: oppPct)
                                }
                            }
                            .frame(height: 6)
                            HStack {
                                Text("对手 \(Int(oppPct * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if challenge.type != .streakSprint {
                                    Text("\(Int(oppPct * Double(challenge.targetCalories))) kcal")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
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

            // 收到的定向挑战：接受按钮
            if challenge.status == .invited && !challenge.isChallenger {
                Button {
                    Task { await acceptDirected(challenge) }
                } label: {
                    Label("接受挑战", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(DS.Colors.accent.opacity(0.14))
                        .foregroundStyle(DS.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .buttonStyle(.plain)
                .padding(.leading, 46)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, DS.Spacing.sm)
        .contextMenu { contextMenuItems(for: challenge) }
    }

    /// 该挑战是否有可执行的管理操作（决定是否显示行内 ••• 菜单）
    private func hasActions(for challenge: PKChallenge) -> Bool {
        if challenge.status == .invited && challenge.isChallenger { return true }
        if challenge.status == .accepted { return true }
        if challenge.status.isTerminal { return true }
        return false
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
                Task { try? await PKSyncService.cancelChallenge(challenge) }
            } label: {
                Label("认输放弃", systemImage: "flag.slash")
            }
        }

        if challenge.status.isTerminal {
            Button(role: .destructive) {
                Task { try? await PKSyncService.deleteChallenge(challenge) }
                modelContext.delete(challenge)
                try? modelContext.save()
            } label: {
                Label("删除记录", systemImage: "trash")
            }
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
                    TextField("我的昵称", text: $claimMyName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("邀请信息")
                } footer: {
                    Text("邀请码可在朋友分享的消息里找到，格式为 XXXX-YYYYYY。认领成功后挑战详情会自动同步。")
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
                    Button("认领") { Task { await claimChallenge() } }
                        .fontWeight(.semibold)
                        .disabled(claimCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSyncing)
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

    @MainActor
    private func createInvite() async {
        let opponent = opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        switch challengeType {
        case .firstToSettle:  title = todayPendingKcal > 0 ? "今日待磨平先结清" : "先结清挑战"
        case .burnTarget:     title = "燃烧 \(Int(targetCalories)) kcal"
        case .streakSprint:   title = "\(Int(durationDays)) 天连续磨平"
        }

        // 先构造但不落库——必须等服务端创建成功、拿到真正的邀请码再保存，
        // 否则对方拿到的是本地占位码、永远认领失败。
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

        isSyncing = true
        defer { isSyncing = false }

        do {
            let result = try await PKSyncService.createChallenge(
                challenge, visibility: postToBoard ? "public" : nil
            )
            challenge.serverId = result.serverId
            challenge.serverInviteCode = result.inviteCode
            modelContext.insert(challenge)
            try? modelContext.save()
            latestInvite = challenge
            opponentName = ""
            postToBoard = false
        } catch PKSyncService.PKSyncError.notLoggedIn {
            syncError = "请先登录账号才能发起挑战"
            showSyncError = true
        } catch {
            syncError = "网络异常，挑战创建失败，请稍后重试"
            showSyncError = true
        }
    }

    @MainActor
    private func claimChallenge() async {
        let code = claimCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let myName = claimMyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isSyncing = true

        do {
            let challenge = try await PKSyncService.claimChallenge(
                inviteCode: code,
                opponentName: myName.isEmpty ? profile.displayName : myName,
                opponentCode: profile.inviteCode
            )
            modelContext.insert(challenge)
            try? modelContext.save()
            showClaimSheet = false
            resetClaimForm()
        } catch PKSyncService.PKSyncError.notLoggedIn {
            syncError = "请先登录账号才能认领挑战"
            showSyncError = true
        } catch PKSyncService.PKSyncError.serverError(let code, let msg) {
            syncError = code == 404 ? "邀请码无效或已被认领" : msg
            showSyncError = true
        } catch {
            syncError = error.localizedDescription
            showSyncError = true
        }

        isSyncing = false
    }

    private func resetClaimForm() {
        claimCode = ""
        claimMyName = profile.displayName
    }

    /// 单一入口：防止 .task / .refreshable / .onReceive 并发重入同步。
    @MainActor
    private func runSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await pullRemoteChallenges()
        await syncActiveChallenges()
    }

    /// 从服务端拉取我参与的全部挑战，合并进本地 SwiftData。
    /// 这样别人发给我的定向挑战、我发的被认领的挑战，本地都能看到。
    @MainActor
    private func pullRemoteChallenges() async {
        guard AuthSessionStore.isAuthenticated else { return }
        let remote: [PKSyncService.RemoteChallenge]
        do { remote = try await PKSyncService.fetchAllChallenges() } catch { return }

        for r in remote {
            if let existing = challenges.first(where: { $0.serverId == r.serverId }) {
                if let st = PKChallengeStatus(rawValue: r.status) { existing.status = st }
                existing.opponentProgress = r.opponentProgress
                existing.myProgress = max(existing.myProgress, r.myProgress)
                if let on = r.opponentName { existing.opponentName = on }
                existing.acceptedAt = r.acceptedAt
                existing.completedAt = r.completedAt
            } else {
                guard let type = PKChallengeType(rawValue: r.type) else { continue }
                let c = PKChallenge(
                    type: type,
                    title: r.title,
                    challengerName: r.challengerName,
                    challengerCode: r.challengerCode,
                    opponentName: r.opponentName,
                    targetCalories: r.targetCalories,
                    durationDays: r.durationDays,
                    status: PKChallengeStatus(rawValue: r.status) ?? .invited,
                    note: r.note,
                    isChallenger: r.iAmChallenger,
                    serverId: r.serverId,
                    serverInviteCode: r.inviteCode
                )
                c.opponentProgress = r.opponentProgress
                c.myProgress = r.myProgress
                c.acceptedAt = r.acceptedAt
                c.completedAt = r.completedAt
                modelContext.insert(c)
            }
        }
        try? modelContext.save()
    }

    /// 接受别人发给我的定向挑战
    @MainActor
    private func acceptDirected(_ challenge: PKChallenge) async {
        guard let serverId = challenge.serverId else { return }
        do {
            try await SocialService.acceptDirectedChallenge(serverId: serverId)
            challenge.status = .accepted
            challenge.acceptedAt = Date()
            try? modelContext.save()
        } catch {
            syncError = (error as? LocalizedError)?.errorDescription ?? "接受失败"
            showSyncError = true
        }
    }

    /// 拉取所有进行中挑战的对手进度并推送我方进度。
    /// 全程在主 actor 上顺序执行：await 网络时会挂起（不阻塞 UI），但绝不在后台线程
    /// 访问 SwiftData @Model 对象——后者会导致真机 hang/crash。
    @MainActor
    private func syncActiveChallenges() async {
        guard AuthSessionStore.isAuthenticated else { return }
        // isSyncing 由 runSync 统一管理（这里不再单独置位，避免被自身守卫挡掉）
        let active = challenges.filter { $0.status == .accepted && $0.serverId != nil }
        for challenge in active {
            // 在主 actor 上先取出纯值
            guard let serverId = challenge.serverId else { continue }
            let isChallenger = challenge.isChallenger
            let myProgress = challenge.myProgress
            do {
                let newOpp = try await PKSyncService.pushProgress(
                    serverId: serverId, isChallenger: isChallenger, myProgress: myProgress
                )
                // 续体在主 actor 上恢复，写回模型是安全的
                challenge.opponentProgress = newOpp
            } catch { }
        }
        try? modelContext.save()
    }

    /// 将 APNs device token 注册到当前所有有 serverId 的挑战（同样全程主 actor）
    @MainActor
    private func registerDeviceTokenForActive(_ token: String) async {
        let serverIds = challenges
            .filter { $0.serverId != nil && !$0.status.isTerminal }
            .compactMap { $0.serverId }
        for serverId in serverIds {
            try? await PKSyncService.registerDeviceToken(token, serverId: serverId)
        }
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
