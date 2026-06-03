import SwiftUI
import LevelItShared

/// 餐次配额配置：编辑三餐时间窗口 + 偏差容差
struct MealQuotaConfigView: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: (() -> Void)?

    @State private var breakfast: WindowDraft = .init(start: .now, end: .now)
    @State private var lunch:     WindowDraft = .init(start: .now, end: .now)
    @State private var dinner:    WindowDraft = .init(start: .now, end: .now)
    @State private var tolerancePct: Double = 10
    @State private var levelingStrategy: LevelingStrategy = .standard
    @State private var validationError: String?

    /// 实时预览的"现在"时间，每 30s 刷新一次
    @State private var nowTick = Date()

    var body: some View {
        Form {
            previewSection
            timeWindowSection
            toleranceSection
            strategySection
            actionsSection
        }
        .navigationTitle("餐次时间设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .disabled(validationError != nil)
                    .fontWeight(.semibold)
            }
        }
        .onAppear { loadFromStore() }
        .onChange(of: breakfast.start) { _, _ in validate() }
        .onChange(of: breakfast.end)   { _, _ in validate() }
        .onChange(of: lunch.start)     { _, _ in validate() }
        .onChange(of: lunch.end)       { _, _ in validate() }
        .onChange(of: dinner.start)    { _, _ in validate() }
        .onChange(of: dinner.end)      { _, _ in validate() }
        .task {
            // 每 30 秒更新一次预览
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                nowTick = Date()
            }
        }
    }

    // MARK: - Sections

    private var previewSection: some View {
        Section {
            HStack {
                Text("现在")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeString(nowTick))
                    .font(.body.monospacedDigit())
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Text("\(currentPreviewKind.emoji) \(currentPreviewKind.displayName)")
                    .font(.body.weight(.medium))
                    .foregroundStyle(currentPreviewKind.isRegularMeal
                                     ? DS.Colors.accent
                                     : .secondary)
            }
        } header: {
            Text("当前判定预览")
        } footer: {
            if currentPreviewKind.isRegularMeal {
                Text("此时拍照识别热量后，将按 \(currentPreviewKind.displayName)配额校验")
            } else {
                Text("此时拍照将作为加餐处理，先使用每日加餐缓冲，超过部分再进入磨平任务")
            }
        }
    }

    private var timeWindowSection: some View {
        Section {
            windowRow(emoji: "🌅", title: "早餐", draft: $breakfast)
            windowRow(emoji: "☀️", title: "午餐", draft: $lunch)
            windowRow(emoji: "🌙", title: "晚餐", draft: $dinner)
        } header: {
            Text("三餐时间窗口")
        } footer: {
            if let err = validationError {
                Text(err)
                    .foregroundStyle(.red)
            } else {
                Text("窗口外拍照按加餐处理。三餐窗口必须按时间先后顺序，不可重叠。")
            }
        }
    }

    private var toleranceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Text("偏差容差")
                    Spacer()
                    Text("±\(Int(tolerancePct))%")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
                Slider(value: $tolerancePct, in: 0...25, step: 1)
                    .tint(DS.Colors.accent)
            }
        } header: {
            Text("热量校验")
        } footer: {
            Text("识别热量在配额 ±\(Int(tolerancePct))% 内视为达标，不进入磨平任务；超出则按缺口生成任务。")
        }
    }

    private var strategySection: some View {
        Section {
            Picker("任务生成偏好", selection: $levelingStrategy) {
                ForEach(LevelingStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack {
                    Text("今日加餐缓冲")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(strategyBufferPreview)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
                Text(levelingStrategy.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("磨平策略")
        } footer: {
            Text("策略只影响加餐/饮料的缓冲额度，不改变三餐时间窗口和正餐配额。")
        }
    }

    private var actionsSection: some View {
        Section {
            Button("恢复默认") {
                loadDefaults()
            }
            .foregroundStyle(DS.Colors.warning)
        }
    }

    // MARK: - Window Row

    private func windowRow(emoji: String, title: String, draft: Binding<WindowDraft>) -> some View {
        HStack {
            Text(emoji)
                .font(.title3)
                .frame(width: 32, alignment: .leading)
            Text(title)
                .frame(width: 44, alignment: .leading)
            Spacer()
            DatePicker("", selection: draft.start, displayedComponents: .hourAndMinute)
                .labelsHidden()
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
            DatePicker("", selection: draft.end, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    // MARK: - 预览：实时分类

    private var currentPreviewKind: MealKind {
        guard let cfg = currentDraftConfig() else {
            return .snack  // 校验失败时降级
        }
        return cfg.mealKind(at: nowTick)
    }

    // MARK: - State <-> Store

    private func loadFromStore() {
        let cfg = MealQuotaConfigStore.current
        breakfast = WindowDraft(window: cfg.windows[.breakfast])
        lunch     = WindowDraft(window: cfg.windows[.lunch])
        dinner    = WindowDraft(window: cfg.windows[.dinner])
        tolerancePct = cfg.toleranceRatio * 100
        levelingStrategy = cfg.levelingStrategy
        validate()
    }

    private func loadDefaults() {
        breakfast = WindowDraft(window: MealKind.defaultWindows[.breakfast])
        lunch     = WindowDraft(window: MealKind.defaultWindows[.lunch])
        dinner    = WindowDraft(window: MealKind.defaultWindows[.dinner])
        tolerancePct = 10
        levelingStrategy = .standard
        validate()
    }

    private func currentDraftConfig() -> MealQuotaConfig? {
        let bw = breakfast.toWindow()
        let lw = lunch.toWindow()
        let dw = dinner.toWindow()

        // 时序约束
        guard bw.startMinutes < bw.endMinutes,
              lw.startMinutes < lw.endMinutes,
              dw.startMinutes < dw.endMinutes,
              bw.endMinutes <= lw.startMinutes,
              lw.endMinutes <= dw.startMinutes
        else {
            return nil
        }

        var cfg = MealQuotaConfig.default
        cfg.windows[.breakfast] = bw
        cfg.windows[.lunch]     = lw
        cfg.windows[.dinner]    = dw
        cfg.toleranceRatio = tolerancePct / 100.0
        cfg.levelingStrategy = levelingStrategy
        return cfg
    }

    private func validate() {
        if currentDraftConfig() != nil {
            validationError = nil
        } else {
            validationError = "请确保每段起始早于结束，且早餐 ≤ 午餐 ≤ 晚餐 不重叠"
        }
    }

    private func save() {
        guard let cfg = currentDraftConfig() else { return }
        MealQuotaConfigStore.save(cfg)
        if let onSaved {
            onSaved()
        } else {
            dismiss()
        }
    }

    // MARK: - Helpers

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private var strategyBufferPreview: String {
        let tdee = UserProfileStore.current?.tdee ?? UserProfile(
            gender: .male,
            age: AppConstants.ProfileDefaults.defaultAge,
            heightCM: AppConstants.ProfileDefaults.defaultHeightCM,
            weightKG: AppConstants.ProfileDefaults.defaultWeightKG,
            activityLevel: .light
        ).tdee
        let cfg = MealQuotaConfig(levelingStrategy: levelingStrategy)
        return "\(cfg.snackBufferCalories(tdee: tdee)) kcal/天"
    }
}

// MARK: - Window Draft（DatePicker 用 Date，存储用 hour/minute；用 draft 做桥接）

private struct WindowDraft: Equatable {
    var start: Date
    var end: Date

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    init(window: MealTimeWindow?) {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let w = window ?? MealTimeWindow(startHour: 8, endHour: 9)
        self.start = cal.date(byAdding: .minute, value: w.startMinutes, to: base) ?? base
        self.end   = cal.date(byAdding: .minute, value: w.endMinutes,   to: base) ?? base
    }

    func toWindow() -> MealTimeWindow {
        let cal = Calendar.current
        let s = cal.dateComponents([.hour, .minute], from: start)
        let e = cal.dateComponents([.hour, .minute], from: end)
        return MealTimeWindow(
            startHour: s.hour ?? 0,
            startMinute: s.minute ?? 0,
            endHour: e.hour ?? 0,
            endMinute: e.minute ?? 0
        )
    }
}
