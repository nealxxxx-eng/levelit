import SwiftUI
import LevelItShared

/// 综合设置：用户档案 + AI 日常消耗估算 + 餐次配置入口
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: (() -> Void)?

    @State private var gender: Gender = .male
    @State private var age: Double = Double(AppConstants.ProfileDefaults.defaultAge)
    @State private var heightCM: Double = Double(AppConstants.ProfileDefaults.defaultHeightCM)
    @State private var weightKG: Double = AppConstants.ProfileDefaults.defaultWeightKG
    @State private var activityLevel: ActivityLevel = .light
    @State private var aiEstimatedTDEE: Int?
    @State private var aiEstimateSummary: String?
    @State private var aiEstimateUpdatedAt: Date?
    @State private var isEstimating = false
    @State private var estimateError: String?
    @State private var saveMessage: String?

    private var draftProfile: UserProfile {
        UserProfile(
            gender: gender,
            age: Int(age),
            heightCM: Int(heightCM),
            weightKG: weightKG,
            activityLevel: activityLevel,
            aiEstimatedTDEE: aiEstimatedTDEE,
            aiEstimateSummary: aiEstimateSummary,
            aiEstimateUpdatedAt: aiEstimateUpdatedAt
        )
    }

    var body: some View {
        Form {
            profileSection
            energySection
            mealConfigSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { saveProfile() }
                    .fontWeight(.semibold)
            }
        }
        .onAppear { loadProfile() }
    }

    private var profileSection: some View {
        Section {
            Picker("性别", selection: genderBinding) {
                ForEach(Gender.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }

            valueSlider(
                title: "年龄",
                value: ageBinding,
                range: Double(AppConstants.ProfileDefaults.minAge)...Double(AppConstants.ProfileDefaults.maxAge),
                step: 1,
                displayValue: "\(Int(age)) 岁"
            )

            valueSlider(
                title: "身高",
                value: heightBinding,
                range: Double(AppConstants.ProfileDefaults.minHeightCM)...Double(AppConstants.ProfileDefaults.maxHeightCM),
                step: 1,
                displayValue: "\(Int(heightCM)) cm"
            )

            valueSlider(
                title: "体重",
                value: weightBinding,
                range: AppConstants.ProfileDefaults.minWeightKG...AppConstants.ProfileDefaults.maxWeightKG,
                step: 0.5,
                displayValue: String(format: "%.1f kg", weightKG)
            )

            Picker("运动强度", selection: activityBinding) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }

            Text(activityLevel.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("使用人信息")
        } footer: {
            Text("这些参数会影响每日消耗、三餐配额和加餐磨平任务的默认计算。")
        }
    }

    private var energySection: some View {
        Section {
            metricRow("基础代谢 BMR", value: "\(draftProfile.bmr) kcal/天")
            metricRow("本地公式 TDEE", value: "\(draftProfile.formulaTDEE) kcal/天")
            metricRow("当前默认 TDEE", value: "\(draftProfile.tdee) kcal/天")

            if let aiEstimatedTDEE {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("阿里后台估算：\(aiEstimatedTDEE) kcal/天")
                        .font(.body.weight(.semibold))
                    if let aiEstimateSummary, !aiEstimateSummary.isEmpty {
                        Text(aiEstimateSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let aiEstimateUpdatedAt {
                        Text("更新时间：\(aiEstimateUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let estimateError {
                Text(estimateError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button {
                estimateDailyEnergy()
            } label: {
                HStack {
                    if isEstimating {
                        ProgressView()
                    }
                    Text(isEstimating ? "正在询问阿里后台..." : "询问阿里后台估算日常消耗")
                }
            }
            .disabled(isEstimating)
        } header: {
            Text("日常消耗")
        } footer: {
            Text("AI 估算成功后会立即保存，并作为 App 当前默认 TDEE；如果之后修改使用人信息，需要重新估算。")
        }
    }

    private var mealConfigSection: some View {
        Section {
            NavigationLink(value: AppRoute.mealQuotaConfig) {
                Label("餐次时间、热量容差与磨平策略", systemImage: "clock.badge.checkmark")
            }
        } header: {
            Text("餐次规则")
        }
    }

    private func valueSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        displayValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text(title)
                Spacer()
                Text(displayValue)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Colors.accent)
            }
            Slider(value: value, in: range, step: step)
                .tint(DS.Colors.accent)
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.medium))
        }
    }

    private var genderBinding: Binding<Gender> {
        Binding(
            get: { gender },
            set: { newValue in
                guard gender != newValue else { return }
                gender = newValue
                clearAIEstimate()
            }
        )
    }

    private var ageBinding: Binding<Double> {
        Binding(
            get: { age },
            set: { newValue in
                guard age != newValue else { return }
                age = newValue
                clearAIEstimate()
            }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { heightCM },
            set: { newValue in
                guard heightCM != newValue else { return }
                heightCM = newValue
                clearAIEstimate()
            }
        )
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { weightKG },
            set: { newValue in
                guard weightKG != newValue else { return }
                weightKG = newValue
                clearAIEstimate()
            }
        )
    }

    private var activityBinding: Binding<ActivityLevel> {
        Binding(
            get: { activityLevel },
            set: { newValue in
                guard activityLevel != newValue else { return }
                activityLevel = newValue
                clearAIEstimate()
            }
        )
    }

    private func loadProfile() {
        let profile = UserProfileStore.current ?? UserProfile(
            gender: .male,
            age: AppConstants.ProfileDefaults.defaultAge,
            heightCM: AppConstants.ProfileDefaults.defaultHeightCM,
            weightKG: AppConstants.ProfileDefaults.defaultWeightKG,
            activityLevel: .light
        )

        gender = profile.gender
        age = Double(profile.age)
        heightCM = Double(profile.heightCM)
        weightKG = profile.weightKG
        activityLevel = profile.activityLevel
        aiEstimatedTDEE = profile.aiEstimatedTDEE
        aiEstimateSummary = profile.aiEstimateSummary
        aiEstimateUpdatedAt = profile.aiEstimateUpdatedAt
    }

    private func clearAIEstimate() {
        aiEstimatedTDEE = nil
        aiEstimateSummary = nil
        aiEstimateUpdatedAt = nil
        estimateError = nil
        saveMessage = "使用人信息已变化，请重新估算日常消耗"
    }

    private func saveProfile() {
        UserProfileStore.save(draftProfile)
        estimateError = nil
        saveMessage = "已保存，默认 TDEE 已更新为 \(draftProfile.tdee) kcal/天"
        if let onSaved {
            onSaved()
        } else {
            dismiss()
        }
    }

    private func estimateDailyEnergy() {
        isEstimating = true
        estimateError = nil
        saveMessage = nil

        Task {
            do {
                let result = try await DailyEnergyEstimateService.estimate(profile: draftProfile)
                await MainActor.run {
                    var updatedProfile = draftProfile
                    updatedProfile.aiEstimatedTDEE = result.estimatedDailyCalories
                    updatedProfile.aiEstimateSummary = result.summary
                    updatedProfile.aiEstimateUpdatedAt = Date()
                    aiEstimatedTDEE = result.estimatedDailyCalories
                    aiEstimateSummary = result.summary
                    aiEstimateUpdatedAt = updatedProfile.aiEstimateUpdatedAt
                    UserProfileStore.save(updatedProfile)
                    saveMessage = "已更新默认 TDEE 为 \(result.estimatedDailyCalories) kcal/天"
                    isEstimating = false
                }
            } catch {
                await MainActor.run {
                    estimateError = error.localizedDescription
                    isEstimating = false
                }
            }
        }
    }
}
