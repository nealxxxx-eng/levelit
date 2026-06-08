import SwiftUI
import LevelItShared

struct AuthGateView: View {
    var onAuthenticated: () -> Void

    @State private var mode: AuthMode = .login
    @State private var identifier = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private enum AuthMode: String, CaseIterable {
        case login = "登录"
        case register = "注册"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(AuthMode.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if mode == .login {
                loginForm
            } else {
                OnboardingProfileView(
                    initialIdentifier: identifier,
                    initialPassword: password
                ) {
                    onAuthenticated()
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private var loginForm: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                Spacer(minLength: 40)

                VStack(spacing: DS.Spacing.sm) {
                    Text("欢迎回来")
                        .font(.largeTitle.weight(.bold))
                    Text("登录账号，同步你的档案和磨平数据。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: DS.Spacing.md) {
                    TextField("手机号或邮箱", text: $identifier)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)

                    SecureField("密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    login()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("登录")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSubmit ? DS.Colors.accent : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                .disabled(!canSubmit || isLoading)

                Button("还没有账号？去注册") {
                    withAnimation { mode = .register }
                }
                .font(.subheadline.weight(.medium))

                Spacer(minLength: 40)
            }
            .padding()
        }
    }

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.count >= 6
    }

    private func login() {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await AliyunAuthService.login(
                    identifier: identifier,
                    password: password
                )
                await MainActor.run {
                    AliyunAuthService.apply(result, identifier: identifier)
                    isLoading = false
                    onAuthenticated()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
