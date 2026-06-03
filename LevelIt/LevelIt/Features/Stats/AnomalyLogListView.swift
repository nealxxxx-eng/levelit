import SwiftUI
import SwiftData
import LevelItShared

/// 异常日历史列表
struct AnomalyLogListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AnomalyLog.date, order: .reverse) private var allLogs: [AnomalyLog]

    @State private var logToDelete: AnomalyLog?

    var body: some View {
        Group {
            if allLogs.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("异常日记录")
        .navigationBarTitleDisplayMode(.inline)
        .alert("删除这条记录？", isPresented: .init(
            get: { logToDelete != nil },
            set: { if !$0 { logToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let log = logToDelete {
                    modelContext.delete(log)
                    try? modelContext.save()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let log = logToDelete {
                Text("\(dateString(log.date)) 的异常记录将被永久删除")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("还没有异常日记录")
                .font(.headline)
            Text("在统计页选中某天可以标记")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var listContent: some View {
        List {
            ForEach(allLogs, id: \.id) { log in
                NavigationLink(value: AppRoute.anomalyLogForm(date: log.date)) {
                    logRow(log)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        logToDelete = log
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func logRow(_ log: AnomalyLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dateString(log.date))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(updatedString(log.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !log.reasonTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(log.reasonTags, id: \.self) { tag in
                        Text("\(tag.emoji) \(tag.displayName)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Colors.accent.opacity(0.12))
                            .foregroundStyle(DS.Colors.accent)
                            .clipShape(Capsule())
                    }
                }
            }

            if !log.freeReason.isEmpty {
                Text(log.freeReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !log.dispositionPlan.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(log.dispositionPlan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd EEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: d)
    }

    private func updatedString(_ d: Date) -> String {
        let now = Date()
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return "今天 \(f.string(from: d))"
        }
        let days = cal.dateComponents([.day], from: d, to: now).day ?? 0
        if days < 7 { return "\(days) 天前" }
        let f = DateFormatter(); f.dateFormat = "M-d"
        return f.string(from: d)
    }
}
