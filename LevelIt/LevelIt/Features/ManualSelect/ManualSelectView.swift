import SwiftUI
import LevelItShared

struct ManualSelectView: View {
    @State private var searchText = ""
    @State private var selectedCategory: FoodCategory?
    @State private var customKcal = ""
    @State private var showCustomInput = false

    var onResult: (FoodAnalysisResult) -> Void

    private var filteredFoods: [PresetFood] {
        var foods = PresetFoodLibrary.allFoods
        if let category = selectedCategory {
            foods = foods.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            foods = foods.filter { $0.name.contains(searchText) }
        }
        return foods
    }

    var body: some View {
        VStack(spacing: 0) {
            // 分类筛选
            categoryPicker

            // 食物列表
            ScrollView {
                LazyVStack(spacing: DS.Spacing.sm) {
                    // 自定义 kcal 入口
                    customKcalCard

                    ForEach(filteredFoods) { food in
                        foodCard(food)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("手动选一个")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索食物")
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                categoryChip(nil, label: "全部")
                ForEach(FoodCategory.allCases, id: \.self) { cat in
                    categoryChip(cat, label: cat.rawValue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, DS.Spacing.sm)
        }
        .background(DS.Colors.cardBackground.opacity(0.5))
    }

    private func categoryChip(_ category: FoodCategory?, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selectedCategory == category ? DS.Colors.accent : DS.Colors.cardBackground)
                .foregroundStyle(selectedCategory == category ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    // MARK: - Custom Kcal

    private var customKcalCard: some View {
        VStack(spacing: DS.Spacing.md) {
            if showCustomInput {
                HStack {
                    TextField("输入热量", text: $customKcal)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)

                    Text("kcal")
                        .foregroundStyle(.secondary)

                    Button("确定") {
                        submitCustom()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Colors.accent)
                    .disabled(customKcal.isEmpty)
                }
            } else {
                Button {
                    showCustomInput = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("自定义热量")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - Food Card

    private func foodCard(_ food: PresetFood) -> some View {
        Button {
            selectFood(food)
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Text(food.emoji)
                    .font(.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.body.weight(.medium))
                    Text(food.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(food.estimatedCalories)")
                        .font(.title3.weight(.bold))
                    Text("kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let level = TaskLevel.from(calories: food.estimatedCalories)
                Circle()
                    .fill(level.color)
                    .frame(width: 12, height: 12)
            }
            .padding()
            .background(DS.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func selectFood(_ food: PresetFood) {
        let result = FoodAnalysisResult(
            foodName: food.name,
            foodEmoji: food.emoji,
            estimatedCalories: food.estimatedCalories,
            imageData: nil
        )
        onResult(result)
    }

    private func submitCustom() {
        guard let kcal = Int(customKcal), kcal > 0 else { return }
        let safeKcal = CalorieCalculator.clampedCalories(kcal)
        customKcal = "\(safeKcal)"
        let result = FoodAnalysisResult(
            foodName: "自定义食物",
            foodEmoji: "🍽️",
            estimatedCalories: safeKcal,
            imageData: nil
        )
        onResult(result)
    }
}
