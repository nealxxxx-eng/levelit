import SwiftUI
import LevelItShared

struct OnboardingProfileView: View {
    var initialIdentifier: String = ""
    var initialPassword: String = ""
    var onComplete: () -> Void

    @State private var step = 0
    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var displayName: String = ""
    @State private var gender: Gender = .male
    @State private var age: Int = AppConstants.ProfileDefaults.defaultAge
    @State private var heightCM: Int = AppConstants.ProfileDefaults.defaultHeightCM
    @State private var weightKG: Double = AppConstants.ProfileDefaults.defaultWeightKG
    @State private var activityLevel: ActivityLevel = .light
    @State private var isSaving = false
    @State private var cloudError: String?

    private let totalSteps = 4

    // 预计算，避免每次渲染重新生成 341 个元素的数组
    private static let weightOptions: [Double] = Array(stride(
        from: AppConstants.ProfileDefaults.minWeightKG,
        through: AppConstants.ProfileDefaults.maxWeightKG,
        by: 0.5
    ))

    private var previewProfile: UserProfile {
        UserProfile(
            displayName: normalizedDisplayName,
            gender: gender,
            age: age,
            heightCM: heightCM,
            weightKG: weightKG,
            activityLevel: activityLevel
        )
    }

    private var normalizedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "LevelIt 用户" : trimmed
    }

    var body: some View {
        VStack(spacing: 0) {
            // 进度条
            progressBar

            // 内容：只渲染当前步骤，避免 TabView 同时创建所有子视图（含滚轮选择器）
            ZStack {
                switch step {
                case 0: genderStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 1: bodyStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 2: activityStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                default: summaryStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: step)

            // 底部按钮
            bottomButtons
        }
        .background(Color(.systemBackground))
        .onAppear {
            if identifier.isEmpty {
                identifier = initialIdentifier
            }
            if password.isEmpty {
                password = initialPassword
            }
        }
    }

    // MARK: - 进度条

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.Colors.accent)
                    .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps))
                    .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
        .frame(height: 4)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Step 0: 性别

    private var genderStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            Text("欢迎使用磨平")
                .font(.largeTitle.weight(.bold))

            Text("先告诉我们一些基本信息\n用于计算你的基础代谢")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("昵称", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, DS.Spacing.xl)

            VStack(spacing: DS.Spacing.md) {
                TextField("手机号或邮箱", text: $identifier)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)

                SecureField("密码（至少 6 位）", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, DS.Spacing.xl)

            HStack(spacing: DS.Spacing.lg) {
                genderCard(.male, icon: "figure.stand", label: "男")
                genderCard(.female, icon: "figure.stand.dress", label: "女")
            }
            .padding(.horizontal, DS.Spacing.xl)

            Spacer()
            Spacer()
        }
    }

    private func genderCard(_ g: Gender, icon: String, label: String) -> some View {
        Button {
            withAnimation { gender = g }
        } label: {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                Text(label)
                    .font(.title3.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xl)
            .background(gender == g ? DS.Colors.accent.opacity(0.15) : DS.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(gender == g ? DS.Colors.accent : .clear, lineWidth: 2)
            )
            .foregroundStyle(gender == g ? DS.Colors.accent : .primary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
    }

    // MARK: - Step 1: 身体数据

    private var bodyStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Text("身体数据")
                .font(.title.weight(.bold))
                .padding(.bottom, DS.Spacing.xs)
            Text("用于计算你的基础代谢率")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 24)

            HStack(spacing: DS.Spacing.md) {
                metricWheelCard(label: "年龄", unit: "岁") {
                    Picker("年龄", selection: $age) {
                        ForEach(AppConstants.ProfileDefaults.minAge...AppConstants.ProfileDefaults.maxAge, id: \.self) { v in
                            Text("\(v)").tag(v)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                metricWheelCard(label: "身高", unit: "cm") {
                    Picker("身高", selection: $heightCM) {
                        ForEach(AppConstants.ProfileDefaults.minHeightCM...AppConstants.ProfileDefaults.maxHeightCM, id: \.self) { v in
                            Text("\(v)").tag(v)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                metricWheelCard(label: "体重", unit: "kg") {
                    Picker("体重", selection: $weightKG) {
                        ForEach(Self.weightOptions, id: \.self) { v in
                            Text(v.truncatingRemainder(dividingBy: 1) == 0
                                 ? "\(Int(v))"
                                 : String(format: "%.1f", v)
                            ).tag(v)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    private func metricWheelCard<Content: View>(label: String, unit: String, @ViewBuilder picker: () -> Content) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            picker()
                .frame(height: 140)
                .clipped()
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Step 2: 活动水平

    private var activityStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            Text("日常活动水平")
                .font(.title.weight(.bold))

            Text("影响每日自然消耗余额的计算")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: DS.Spacing.md) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    activityRow(level)
                }
            }
            .padding(.horizontal)

            Spacer()
            Spacer()
        }
    }

    private func activityRow(_ level: ActivityLevel) -> some View {
        Button {
            withAnimation { activityLevel = level }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: activityIcon(level))
                    .font(.title2)
                    .foregroundStyle(activityLevel == level ? DS.Colors.accent : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.body.weight(.medium))
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if activityLevel == level {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Colors.accent)
                }
            }
            .padding()
            .background(activityLevel == level ? DS.Colors.accent.opacity(0.1) : DS.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(activityLevel == level ? DS.Colors.accent : .clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func activityIcon(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: return "chair.fill"
        case .light:     return "figure.walk"
        case .moderate:  return "figure.run"
        case .active:    return "figure.highintensity.intervaltraining"
        }
    }

    // MARK: - Step 3: 汇总确认

    private var summaryStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            Text("你的基础代谢")
                .font(.title.weight(.bold))

            // BMR 大数字
            VStack(spacing: DS.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(previewProfile.bmr)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.accent)
                    Text("kcal/天")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text("基础代谢率 (BMR)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 每日自然余额
            VStack(spacing: DS.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(previewProfile.dailyAllowance)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("kcal/天")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("每日自然消耗余额")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("这部分热量每天由身体自然消耗，可以抵消零食和加餐")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // 档案汇总
            VStack(spacing: DS.Spacing.sm) {
                summaryRow("昵称", value: normalizedDisplayName)
                summaryRow("性别", value: gender.displayName)
                summaryRow("年龄", value: "\(age) 岁")
                summaryRow("身高", value: "\(heightCM) cm")
                summaryRow("体重", value: String(format: "%.1f kg", weightKG))
                summaryRow("活动水平", value: activityLevel.displayName)
            }
            .padding()
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .padding(.horizontal)

            if let error = cloudError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    // MARK: - 底部按钮

    private var bottomButtons: some View {
        HStack(spacing: DS.Spacing.md) {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Text("上一步")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Colors.cardBackground)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
            }

            Button {
                if step < totalSteps - 1 {
                    if step == 0, !accountInputIsValid {
                        cloudError = "请填写手机号或邮箱，并设置至少 6 位密码"
                        return
                    }
                    cloudError = nil
                    withAnimation { step += 1 }
                } else {
                    saveProfile()
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(step < totalSteps - 1 ? "下一步" : "开始使用")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(DS.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
            .disabled(isSaving)
        }
        .padding()
    }

    // MARK: - 保存

    private func saveProfile() {
        guard accountInputIsValid else {
            cloudError = "请填写手机号或邮箱，并设置至少 6 位密码"
            return
        }

        isSaving = true
        cloudError = nil

        let profile = previewProfile

        Task {
            do {
                let result = try await AliyunAuthService.register(
                    identifier: identifier,
                    password: password,
                    profile: profile
                )
                await MainActor.run {
                    AliyunAuthService.apply(result, identifier: identifier)
                    isSaving = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    cloudError = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private var accountInputIsValid: Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.count >= 6
    }
}
