import WidgetKit
import SwiftUI
import SwiftData
import LevelItShared

/// Complication 数据
struct DebtEntry: TimelineEntry {
    let date: Date
    let pendingKcal: Int
}

/// Timeline Provider
struct DebtTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DebtEntry {
        DebtEntry(date: .now, pendingKcal: 280)
    }

    func getSnapshot(in context: Context, completion: @escaping (DebtEntry) -> Void) {
        let kcal = fetchPendingKcal()
        completion(DebtEntry(date: .now, pendingKcal: kcal))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DebtEntry>) -> Void) {
        let kcal = fetchPendingKcal()
        let entry = DebtEntry(date: .now, pendingKcal: kcal)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    /// 从 SwiftData 读取真实欠债 kcal
    private func fetchPendingKcal() -> Int {
        guard let container = try? ModelContainer(for: DebtTask.self) else { return 0 }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<DebtTask>()
        guard let tasks = try? context.fetch(descriptor) else { return 0 }
        return tasks
            .filter { $0.isPendingForDay() }
            .reduce(0) { $0 + max(0, $1.estimatedCalories - $1.burnedCalories) }
    }
}

/// Complication Widget
struct DebtComplicationWidget: Widget {
    let kind = "DebtComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DebtTimelineProvider()) { entry in
            DebtComplicationView(entry: entry)
        }
        .configurationDisplayName("今日欠债")
        .description("显示待磨平的热量")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
        ])
    }
}

/// Complication 视图
struct DebtComplicationView: View {
    let entry: DebtEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(entry.pendingKcal)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("kcal")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .widgetAccentable()
    }

    private var cornerView: some View {
        Text("\(entry.pendingKcal)")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .widgetAccentable()
            .widgetLabel {
                Text("kcal 待磨平")
            }
    }

    private var rectangularView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("磨平")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(entry.pendingKcal) kcal")
                    .font(.headline)
                    .widgetAccentable()
                Text("待磨平")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
