import SwiftUI
import LevelItShared

/// 正餐超标后的"热量缺口确认"页
///
/// 上游：AnalysisView 的 MealClassifier 判定为 .overMeal 时跳转到这里。
/// 下游：用户确认 → push taskMode(adjustedResult)；调到 0 → popToRoot 直接返回首页。
struct MealOverConfirmView: View {
    @Environment(\.popToRoot) private var popToRoot
    @Environment(\.dismiss) private var dismiss

    let originalResult: FoodAnalysisResult
    let mealKind: MealKind
    let actualKcal: Int
    let gapKcal: Int
    let accumulatedBefore: Int
    let intakeId: String?
    var onConfirm: (FoodAnalysisResult, String?) -> Void

    @State private var debtKcal: Double

    init(
        originalResult: FoodAnalysisResult,
        mealKind: MealKind,
        actualKcal: Int,
        gapKcal: Int,
        accumulatedBefore: Int = 0,
        intakeId: String? = nil,
        onConfirm: @escaping (FoodAnalysisResult, String?) -> Void
    ) {
        self.originalResult = originalResult
        self.mealKind = mealKind
        self.actualKcal = actualKcal
        self.gapKcal = gapKcal
        self.accumulatedBefore = accumulatedBefore
        self.intakeId = intakeId
        self.onConfirm = onConfirm
        _debtKcal = State(initialValue: Double(gapKcal))
    }

    private var quotaUpper: Int { actualKcal - gapKcal }
    private var thisShotKcal: Int { actualKcal - accumulatedBefore }
    private var hasAccumulation: Bool { accumulatedBefore > 0 }

    /// 调到 0 = 不还债，直接返回
    private var willCancel: Bool { Int(debtKcal) <= 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                headerCard
                if hasAccumulation {
                    accumulationBanner
                }
                breakdownCard
                sliderCard
                ctaButton
                if !willCancel {
                    skipButton
                }
            }
            .padding()
        }
        .navigationTitle("超出配额")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accumulationBanner: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "plus.square.on.square")
                .font(.title3)
                .foregroundStyle(DS.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("本餐累计触发")
                    .font(.subheadline.weight(.medium))
                Text("之前已记录 \(accumulatedBefore) kcal，本张 +\(thisShotKcal) kcal，累计 \(actualKcal) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(DS.Colors.warning.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: DS.Spacing.sm) {
            Text(mealKind.emoji)
                .font(.system(size: 56))
            Text("\(mealKind.displayName)超标")
                .font(.title2.weight(.bold))
            Text("超出配额上限 \(gapKcal) kcal")
                .font(.subheadline)
                .foregroundStyle(DS.Colors.warning)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.xl)
        .background(DS.Colors.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
    }

    // MARK: - Breakdown

    private var breakdownCard: some View {
        VStack(spacing: DS.Spacing.sm) {
            row(label: "本餐识别热量", value: "\(actualKcal) kcal", color: .primary)
            Divider()
            row(label: "配额上限（含 +10% 容差）", value: "\(quotaUpper) kcal", color: .secondary)
            Divider()
            row(
                label: "建议磨平缺口",
                value: "\(gapKcal) kcal",
                color: DS.Colors.warning,
                bold: true
            )
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func row(label: String, value: String, color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(bold ? .bold : .medium))
                .foregroundStyle(color)
        }
    }

    // MARK: - Slider

    private var sliderCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("调整磨平额度")
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(debtKcal))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(willCancel ? .secondary : DS.Colors.warning)
                Text("kcal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                if willCancel {
                    Text("不还了")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
            }

            Slider(
                value: $debtKcal,
                in: 0...Double(max(actualKcal, gapKcal)),
                step: 10
            )
            .tint(DS.Colors.warning)

            HStack {
                Text("0")
                Spacer()
                Text("建议 \(gapKcal)")
                Spacer()
                Text("\(actualKcal)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            // 快捷选项
            HStack(spacing: DS.Spacing.sm) {
                quickButton("不还", value: 0)
                quickButton("一半", value: max(1, gapKcal / 2))
                quickButton("缺口", value: gapKcal)
                quickButton("全部", value: actualKcal)
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func quickButton(_ title: String, value: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                debtKcal = Double(value)
            }
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Int(debtKcal) == value
                            ? DS.Colors.warning.opacity(0.2)
                            : Color.gray.opacity(0.08))
                .foregroundStyle(Int(debtKcal) == value
                                 ? DS.Colors.warning
                                 : .primary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            if willCancel {
                popToRoot()
            } else {
                onConfirm(makeAdjustedResult(), intakeId)
            }
        } label: {
            Text(willCancel ? "返回首页" : "进入磨平任务（\(Int(debtKcal)) kcal）")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(willCancel ? Color.gray : DS.Colors.warning)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
    }

    private var skipButton: some View {
        Button("这次先放过自己") {
            popToRoot()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - 构造下游 result

    /// 把 debtKcal 作为最终 estimatedCalories 喂给 TaskModeView，
    /// 食物名后追加 (磨平缺口) 让用户在结果页能识别这是分流后的任务。
    private func makeAdjustedResult() -> FoodAnalysisResult {
        FoodAnalysisResult(
            foodName: "\(originalResult.foodName)（\(mealKind.displayName)缺口）",
            foodEmoji: originalResult.foodEmoji,
            estimatedCalories: max(AppConstants.minCalories, Int(debtKcal)),
            imageData: originalResult.imageData
        )
    }
}
