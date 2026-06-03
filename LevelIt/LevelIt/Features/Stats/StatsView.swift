import SwiftUI
import SwiftData
import Charts
import HealthKit
import LevelItShared

struct StatsView: View {
    @Query(sort: \DebtTask.createdAt, order: .reverse) private var allTasks: [DebtTask]
    @Query(sort: \MealIntake.takenAt, order: .reverse) private var allIntakes: [MealIntake]
    @Query(sort: \AnomalyLog.date, order: .reverse) private var allAnomalyLogs: [AnomalyLog]
    @State private var period: StatsPeriod = .week
    @State private var selectedDay: String?

    private var store: HealthKitDataStore { .shared }

    /// 选中日期对应的实际 Date（从 dailyData label 反查）
    private var selectedDate: Date? {
        guard let selected = selectedDay else { return nil }
        return dailyData.first(where: { $0.label == selected })?.date
    }

    /// 选中日期当天的异常日记录（如有）
    private var anomalyForSelectedDay: AnomalyLog? {
        guard let date = selectedDate else { return nil }
        let cal = Calendar.current
        return allAnomalyLogs.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    /// 当前时间范围内的异常日（按 label 索引，便于柱图叠加）
    private var anomalyLabelsInPeriod: Set<String> {
        let cal = Calendar.current
        let labels = dailyData.compactMap { entry -> String? in
            allAnomalyLogs.contains { cal.isDate($0.date, inSameDayAs: entry.date) }
                ? entry.label
                : nil
        }
        return Set(labels)
    }

    enum StatsPeriod: String, CaseIterable {
        case week = "本周"
        case month = "本月"
    }

    // MARK: - 时间范围

    private var periodStart: Date {
        let calendar = Calendar.current
        let now = Date()
        switch period {
        case .week:
            return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        }
    }

    // MARK: - 任务指标（DebtTask）

    private var tasksInPeriod: [DebtTask] {
        allTasks.filter { $0.createdAt >= periodStart }
    }

    private var taskCount: Int { tasksInPeriod.count }

    // MARK: - 摄入指标（MealIntake，全口径含未生成磨平任务的）

    private var intakesInPeriod: [MealIntake] {
        allIntakes.filter { $0.takenAt >= periodStart }
    }

    private var totalIntake: Int {
        intakesInPeriod.reduce(0) { $0 + max(0, $1.estimatedCalories) }
    }

    private var settledCount: Int {
        tasksInPeriod.filter { $0.status == .settled || $0.status == .completed }.count
    }

    private var completionRate: Int {
        guard taskCount > 0 else { return 0 }
        return Int(Double(settledCount) / Double(taskCount) * 100)
    }

    // MARK: - HealthKit 侧（消耗, 从 store 读取）

    private var hkWorkouts: [HealthKitImportService.WorkoutSummary] {
        store.periodWorkouts
    }

    private var totalBurned: Int {
        hkWorkouts.reduce(0) { $0 + $1.calories }
    }

    /// 周期内自然消耗额度 (天数 × 每日余额)
    private var totalNaturalAllowance: Int {
        let days = max(1, Calendar.current.dateComponents([.day], from: periodStart, to: Date()).day ?? 1)
        return NaturalAllowance.dailyTotal * days
    }

    private var totalConsumed: Int {
        totalBurned + totalNaturalAllowance
    }

    private var totalDurationMinutes: Int {
        Int(hkWorkouts.reduce(0.0) { $0 + $1.duration }) / 60
    }

    private var workoutCount: Int { hkWorkouts.count }

    private var topWorkoutTypes: [(String, String, Int, Int)] {
        var counts: [HKWorkoutActivityType: (count: Int, calories: Int)] = [:]
        for w in hkWorkouts {
            let existing = counts[w.activityType, default: (0, 0)]
            counts[w.activityType] = (existing.count + 1, existing.calories + w.calories)
        }
        return counts.sorted { $0.value.calories > $1.value.calories }
            .prefix(5)
            .map { ($0.key.displayName, $0.key.iconName, $0.value.count, $0.value.calories) }
    }

    // MARK: - 每日趋势数据

    private var dailyData: [DailyEntry] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = period == .week ? "E" : "d"

        let days = period == .week ? 7 : (calendar.range(of: .day, in: .month, for: Date())?.count ?? 30)
        let now = Date()

        var result: [DailyEntry] = []
        for i in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            // 摄入：MealIntake 全口径
            let intake = MealIntakeAggregator.dailyTotalKcal(
                from: allIntakes, on: date, calendar: calendar
            )
            let burned = hkWorkouts
                .filter { calendar.isDate($0.startDate, inSameDayAs: date) }
                .reduce(0) { $0 + $1.calories }
            let label = formatter.string(from: date)
            result.append(DailyEntry(label: label, intake: intake, burned: burned, date: date))
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                anomalyEntryRow

                Picker("", selection: $period) {
                    ForEach(StatsPeriod.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                calorieRingCard
                keyMetrics
                dailyBarChart
                anomalyActionButton
                balanceTrendChart

                if !topWorkoutTypes.isEmpty {
                    workoutBreakdown
                }
            }
            .padding()
        }
        .task(id: period) {
            await store.refreshPeriodWorkouts(start: periodStart, end: Date())
        }
    }

    // MARK: - 异常日入口

    private var anomalyEntryRow: some View {
        NavigationLink(value: AppRoute.anomalyLogList) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("异常日记录")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(allAnomalyLogs.isEmpty
                         ? "标记某天为异常并记录原因/处置方案"
                         : "已记录 \(allAnomalyLogs.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var anomalyActionButton: some View {
        if let date = selectedDate {
            NavigationLink(value: AppRoute.anomalyLogForm(date: date)) {
                HStack {
                    Image(systemName: anomalyForSelectedDay != nil
                          ? "pencil.circle.fill"
                          : "exclamationmark.circle")
                    Text(anomalyForSelectedDay != nil
                         ? "编辑「\(shortDate(date))」异常记录"
                         : "标记「\(shortDate(date))」为异常日")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(.orange)
                .padding()
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
            .buttonStyle(.plain)
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M-d"
        return f.string(from: d)
    }

    // MARK: - 热量环形仪表盘

    private var calorieRingCard: some View {
        let ratio = totalIntake > 0 ? min(2.0, Double(totalConsumed) / Double(totalIntake)) : 0
        let isPositive = totalConsumed >= totalIntake
        let diff = totalConsumed - totalIntake

        return VStack(spacing: DS.Spacing.md) {
            Text("热量收支")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DS.Spacing.xl) {
                // 环形图
                ZStack {
                    Circle()
                        .stroke(Color.red.opacity(0.15), lineWidth: 12)

                    Circle()
                        .trim(from: 0, to: min(1.0, ratio))
                        .stroke(
                            isPositive ? Color.green : DS.Colors.accent,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: ratio)

                    VStack(spacing: 2) {
                        Text("\(isPositive ? "+" : "")\(diff)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(isPositive ? Color.green : Color.orange)

                        Text("kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 100, height: 100)

                // 数字
                VStack(spacing: DS.Spacing.md) {
                    HStack(spacing: DS.Spacing.sm) {
                        Circle().fill(.red.opacity(0.6)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("摄入")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if store.isLoadingPeriod {
                                ProgressView().frame(height: 20)
                            } else {
                                Text("\(totalIntake) kcal")
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    HStack(spacing: DS.Spacing.sm) {
                        Circle().fill(DS.Colors.accent).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("运动消耗")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if store.isLoadingPeriod {
                                ProgressView().frame(height: 20)
                            } else {
                                Text("\(totalBurned) kcal")
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .foregroundStyle(DS.Colors.accent)
                            }
                        }
                    }

                    if totalNaturalAllowance > 0 {
                        HStack(spacing: DS.Spacing.sm) {
                            Circle().fill(.green).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自然消耗")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(totalNaturalAllowance) kcal")
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 关键数据

    private var keyMetrics: some View {
        HStack(spacing: 0) {
            metricItem(value: "\(taskCount)", label: "任务数")
            Divider().frame(height: 36)
            metricItem(value: "\(settledCount)", label: "已结清")
            Divider().frame(height: 36)
            metricItem(value: "\(completionRate)%", label: "完成率")
            Divider().frame(height: 36)
            metricItem(value: "\(workoutCount)", label: "运动次数")
            Divider().frame(height: 36)
            metricItem(value: "\(totalDurationMinutes)", label: "分钟")
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func metricItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 每日柱状图 (SwiftUI Charts)

    private var dailyBarChart: some View {
        let data = dailyData
        let anomalyLabels = anomalyLabelsInPeriod

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("每日趋势")
                    .font(.headline)
                Spacer()
                if !anomalyLabels.isEmpty {
                    HStack(spacing: 4) {
                        Text("⚠️")
                        Text("含 \(anomalyLabels.count) 天异常")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Chart {
                ForEach(data) { entry in
                    BarMark(
                        x: .value("日期", entry.label),
                        y: .value("热量", entry.intake)
                    )
                    .foregroundStyle(.red.opacity(0.7))
                    .position(by: .value("类型", "摄入"))

                    BarMark(
                        x: .value("日期", entry.label),
                        y: .value("热量", entry.burned)
                    )
                    .foregroundStyle(DS.Colors.accent)
                    .position(by: .value("类型", "消耗"))

                    // 异常日标记：在该日柱顶上方放一个 ⚠️
                    if anomalyLabels.contains(entry.label) {
                        PointMark(
                            x: .value("日期", entry.label),
                            y: .value("热量", max(entry.intake, entry.burned))
                        )
                        .symbol {
                            Text("⚠️").font(.caption2)
                        }
                        .annotation(position: .top, spacing: 2) {
                            EmptyView()
                        }
                    }
                }

                if let selected = selectedDay,
                   let entry = data.first(where: { $0.label == selected }) {
                    RuleMark(x: .value("日期", selected))
                        .foregroundStyle(.gray.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top, spacing: 4) {
                            VStack(spacing: 2) {
                                Text("摄入 \(entry.intake)")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                Text("消耗 \(entry.burned)")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Colors.accent)
                            }
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                }
            }
            .chartXSelection(value: $selectedDay)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 180)

            // 图例
            HStack(spacing: DS.Spacing.md) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(.red.opacity(0.7)).frame(width: 12, height: 8)
                    Text("摄入").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(DS.Colors.accent).frame(width: 12, height: 8)
                    Text("消耗").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 净平衡趋势线

    private var balanceTrendChart: some View {
        let data = dailyData

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("净平衡趋势")
                    .font(.headline)
                Spacer()
                let total = data.reduce(0) { $0 + ($1.burned - $1.intake) }
                Text(total >= 0 ? "+\(total)" : "\(total)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(total >= 0 ? .green : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((total >= 0 ? Color.green : Color.orange).opacity(0.15))
                    .clipShape(Capsule())
            }

            Chart {
                ForEach(data) { entry in
                    let balance = entry.burned - entry.intake
                    LineMark(
                        x: .value("日期", entry.label),
                        y: .value("净平衡", balance)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.green, DS.Colors.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    AreaMark(
                        x: .value("日期", entry.label),
                        y: .value("净平衡", balance)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [
                                (balance >= 0 ? Color.green : Color.orange).opacity(0.2),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("日期", entry.label),
                        y: .value("净平衡", balance)
                    )
                    .foregroundStyle(balance >= 0 ? .green : .orange)
                    .symbolSize(24)
                }

                // 零基线
                RuleMark(y: .value("零线", 0))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - 运动类型分布（水平条形图）

    private var workoutBreakdown: some View {
        let maxCal = topWorkoutTypes.map(\.3).max() ?? 1

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("运动类型分布")
                .font(.headline)

            ForEach(Array(topWorkoutTypes.enumerated()), id: \.offset) { index, item in
                let (name, icon, count, calories) = item
                VStack(spacing: 6) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: icon)
                            .font(.body)
                            .foregroundStyle(DS.Colors.accent)
                            .frame(width: 24)

                        Text(name)
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        Text("\(calories) kcal")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DS.Colors.accent)

                        Text("\(count)次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DS.Colors.accent.opacity(0.1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [DS.Colors.accent, DS.Colors.accent.opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * max(0.03, CGFloat(calories) / CGFloat(maxCal)))
                                .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.08), value: calories)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }
}

// MARK: - Data Model

private struct DailyEntry: Identifiable {
    let id = UUID()
    let label: String
    let intake: Int
    let burned: Int
    let date: Date
}
