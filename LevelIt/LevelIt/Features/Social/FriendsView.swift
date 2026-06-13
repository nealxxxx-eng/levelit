import SwiftUI
import SwiftData
import LevelItShared

struct FriendsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var myUsername: String = AuthSessionStore.current?.username ?? ""
    @State private var editingUsername = false
    @State private var usernameDraft = ""

    @State private var searchText = ""
    @State private var searchResults: [SocialService.UserSummary] = []
    @State private var isSearching = false

    @State private var incoming: [SocialService.FriendRequestItem] = []
    @State private var outgoing: [SocialService.FriendRequestItem] = []
    @State private var friends: [SocialService.UserSummary] = []

    @State private var challengeTarget: SocialService.UserSummary?
    @State private var errorText: String?
    @State private var showError = false
    @State private var loading = false

    private var profile: UserProfile {
        UserProfileStore.current ?? UserProfile(
            gender: .male,
            age: AppConstants.ProfileDefaults.defaultAge,
            heightCM: AppConstants.ProfileDefaults.defaultHeightCM,
            weightKG: AppConstants.ProfileDefaults.defaultWeightKG,
            activityLevel: .light
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                usernameCard
                searchCard
                if !incoming.isEmpty { requestsSection }
                friendsSection
            }
            .padding()
        }
        .navigationTitle("好友")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $challengeTarget) { target in
            FriendChallengeSheet(target: target, profile: profile) {
                challengeTarget = nil
            }
        }
        .alert("提示", isPresented: $showError) {
            Button("好的", role: .cancel) {}
        } message: { Text(errorText ?? "出错了") }
    }

    // MARK: - 用户名

    private var usernameCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("我的用户名").font(.headline)
            if editingUsername {
                HStack {
                    TextField("3–20 位，字母开头", text: $usernameDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button("保存") { Task { await saveUsername() } }
                        .disabled(usernameDraft.count < 3 || loading)
                }
            } else {
                HStack {
                    Text(myUsername.isEmpty ? "未设置" : "@\(myUsername)")
                        .font(.body.monospaced())
                        .foregroundStyle(myUsername.isEmpty ? .secondary : .primary)
                    Spacer()
                    Button(myUsername.isEmpty ? "设置" : "修改") {
                        usernameDraft = myUsername
                        editingUsername = true
                    }
                }
            }
            Text("好友通过用户名找到你并发起 PK。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding().background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 搜索加好友

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("加好友").font(.headline)
            HStack {
                TextField("输入对方用户名", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await runSearch() } }
                Button { Task { await runSearch() } } label: {
                    Image(systemName: "magnifyingglass")
                }.disabled(searchText.count < 2 || isSearching)
            }
            ForEach(searchResults) { user in
                HStack {
                    VStack(alignment: .leading) {
                        Text(user.displayName).font(.subheadline.weight(.medium))
                        Text("@\(user.username)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("加好友") { Task { await addFriend(user.username) } }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            if !outgoing.isEmpty {
                Text("已发送的请求").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(outgoing) { req in
                    HStack {
                        Text("@\(req.user.username)").font(.caption.monospaced())
                        Spacer()
                        Text("等待确认").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding().background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 收到的请求

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("好友请求").font(.headline).padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(Array(incoming.enumerated()), id: \.element.id) { i, req in
                    if i > 0 { Divider() }
                    HStack {
                        VStack(alignment: .leading) {
                            Text(req.user.displayName).font(.subheadline.weight(.medium))
                            Text("@\(req.user.username)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("接受") { Task { await accept(req.id) } }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("拒绝") { Task { await reject(req.id) } }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding()
                }
            }
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
    }

    // MARK: - 好友列表

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("我的好友 (\(friends.count))").font(.headline).padding(.horizontal)
            if friends.isEmpty {
                Text("还没有好友，搜索用户名加好友吧。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, DS.Spacing.xl)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(friends.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { Divider().padding(.leading) }
                        HStack {
                            VStack(alignment: .leading) {
                                Text(f.displayName).font(.subheadline.weight(.medium))
                                Text("@\(f.username)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                challengeTarget = f
                            } label: {
                                Label("PK", systemImage: "flame.fill").font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        }
                        .padding()
                        .swipeActions {
                            Button(role: .destructive) { Task { await removeFriend(f.username) } } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .background(DS.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
        }
    }

    // MARK: - 操作

    private func reload() async {
        do {
            async let reqs = SocialService.friendRequests()
            async let fr = SocialService.friends()
            let (r, f) = try await (reqs, fr)
            incoming = r.incoming; outgoing = r.outgoing; friends = f
        } catch { surface(error) }
        myUsername = AuthSessionStore.current?.username ?? myUsername
    }

    private func saveUsername() async {
        loading = true; defer { loading = false }
        do {
            try await SocialService.setUsername(usernameDraft.lowercased())
            myUsername = usernameDraft.lowercased()
            editingUsername = false
        } catch { surface(error) }
    }

    private func runSearch() async {
        isSearching = true; defer { isSearching = false }
        do { searchResults = try await SocialService.searchUsers(searchText) }
        catch { surface(error) }
    }

    private func addFriend(_ username: String) async {
        do { try await SocialService.sendFriendRequest(username: username); await reload(); searchResults = [] }
        catch { surface(error) }
    }
    private func accept(_ id: String) async {
        do { try await SocialService.acceptRequest(id: id); await reload() } catch { surface(error) }
    }
    private func reject(_ id: String) async {
        do { try await SocialService.rejectRequest(id: id); await reload() } catch { surface(error) }
    }
    private func removeFriend(_ username: String) async {
        do { try await SocialService.removeFriend(username: username); await reload() } catch { surface(error) }
    }

    private func surface(_ error: Error) {
        errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showError = true
    }
}
