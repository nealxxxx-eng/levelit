import SwiftUI
import LevelItShared

struct OnboardingProfileView: View {
    var onComplete: () -> Void

    @State private var step = 0
    @State private var gender: Gender = .male
    @State private var age: Double = Double(AppConstants.ProfileDefaults.defaultAge)
    @State private var heightCM: Double = Double(AppConstants.ProfileDefaults.defaultHeightCM)
    @State private var weightKG: Double = AppConstants.ProfileDefaults.defaultWeightKG
    @State private var activityLevel: ActivityLevel = .light
    @State private var isSaving = false
    @State private var cloudError: String?

    private let totalSteps = 4

    private var previewProfile: UserProfile {
        UserProfile(
            gender: gender,
            age: Int(age),
            heightCM: Int(heightCM),
            weightKG: weightKG,
            activityLevel: activityLevel
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 进度条
            progressBar

            // 内容
            TabView(selection: $step) {
                genderStep.tag(0)
                bodyStep.tag(1)
                activityStep.tag(2)
                summaryStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: step)

            // 底部按钮
            bottomButtons
        }
        .background(Color(.systemBackground))
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
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            Text("身体数据")
                .font(.title.weight(.bold))

            VStack(spacing: DS.Spacing.lg) {
                // 年龄
                VStack(spacing: DS.Spacing.sm) {
                    HStack {
                        Text("年龄")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(age)) 岁")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    Slider(
                        value: $age,
                        in: Double(AppConstants.ProfileDefaults.minAge)...Double(AppConstants.ProfileDefaults.maxAge),
                        step: 1
                    )
                    .tint(DS.Colors.accent)
                }

                // 身高
                VStack(spacing: DS.Spacing.sm) {
                    HStack {
                        Text("身高")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(heightCM)) cm")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    Slider(
                        value: $heightCM,
                        in: Double(AppConstants.ProfileDefaults.minHeightCM)...Double(AppConstants.ProfileDefaults.maxHeightCM),
                        step: 1
                    )
                    .tint(DS.Colors.accent)
                }

                // 体重
                VStack(spacing: DS.Spacing.sm) {
                    HStack {
                        Text("体重")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.1f kg", weightKG))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    Slider(
                        value: $weightKG,
                        in: AppConstants.ProfileDefaults.minWeightKG...AppConstants.ProfileDefaults.maxWeightKG,
                        step: 0.5
                    )
                    .tint(DS.Colors.accent)
                }
            }
            .padding()
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .padding(.horizontal)

            Spacer()
            Spacer()
        }
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
                summaryRow("性别", value: gender.displayName)
                summaryRow("年龄", value: "\(Int(age)) 岁")
                summaryRow("身高", value: "\(Int(heightCM)) cm")
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
        isSaving = true
        cloudError = nil

        let profile = previewProfile

        // 1. 立即保存到本地
        UserProfileStore.save(profile)

        // 2. 异步保存到 CloudKit (不阻塞)
        Task {
            do {
                try await CloudKitService.save(profile)
            } catch {
                // CloudKit 失败不阻塞注册流程，本地已保存
                print("CloudKit save failed: \(error.localizedDescription)")
            }
            await MainActor.run {
                isSaving = false
                onComplete()
            }
        }
    }
}
