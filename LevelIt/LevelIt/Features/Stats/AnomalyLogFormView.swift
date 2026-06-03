import SwiftUI
import SwiftData
import LevelItShared

/// 异常日录入/编辑表单
///
/// 入口：StatsView 选中柱状图某天后点"标记本日异常"。
/// 同一天只允许一条 AnomalyLog；如已存在则进入编辑模式。
struct AnomalyLogFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 异常归属日期（startOfDay 在 init 里归一）
    let date: Date

    @Query private var allLogs: [AnomalyLog]

    @State private var selectedTags: Set<AnomalyReasonTag> = []
    @State private var freeReason: String = ""
    @State private var dispositionPlan: String = ""
    @State private var didLoad = false
    @State private var showDeleteConfirm = false

    private let calendar = Calendar.current

    private var normalizedDate: Date {
        calendar.startOfDay(for: date)
    }

    /// 同一天已有记录 → 编辑；否则新建
    private var existingLog: AnomalyLog? {
        allLogs.first { calendar.isDate($0.date, inSameDayAs: normalizedDate) }
    }

    private var isEditing: Bool { existingLog != nil }

    private var canSave: Bool {
        !selectedTags.isEmpty || !freeReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            dateSection
            tagsSection
            reasonSection
            planSection
            if isEditing {
                deleteSection
            }
        }
        .navigationTitle(isEditing ? "编辑异常日" : "标记异常日")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onAppear { loadDraft() }
        .alert("删除这条异常日记录？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { delete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(dateString(normalizedDate))的异常记录将被永久删除")
        }
    }

    // MARK: - Sections

    private var dateSection: some View {
        Section {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(DS.Colors.accent)
                Text(dateString(normalizedDate))
                    .font(.body.weight(.medium))
                Spacer()
                if isEditing {
                    Text("编辑")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DS.Colors.accent.opacity(0.15))
                        .foregroundStyle(DS.Colors.accent)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var tagsSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(AnomalyReasonTag.allCases, id: \.self) { tag in
                    tagChip(tag)
                }
            }
        } header: {
            Text("原因（可多选）")
        } footer: {
            Text("至少选一个标签或填写自由原因")
        }
    }

    private func tagChip(_ tag: AnomalyReasonTag) -> some View {
        let isSelected = selectedTags.contains(tag)
        return Button {
            if isSelected {
                selectedTags.remove(tag)
            } else {
                selectedTags.insert(tag)
            }
        } label: {
            HStack(spacing: 4) {
                Text(tag.emoji)
                Text(tag.displayName)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected
                        ? DS.Colors.accent.opacity(0.2)
                        : Color.gray.opacity(0.1))
            .foregroundStyle(isSelected ? DS.Colors.accent : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var reasonSection: some View {
        Section {
            TextField("自由描述（可选）", text: $freeReason, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("详细原因")
        }
    }

    private var planSection: some View {
        Section {
            TextField("处置方案（可选）", text: $dispositionPlan, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("处置方案")
        } footer: {
            Text("例如：明天加 30 分钟有氧 / 下周三再聚餐")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("删除此记录")
                }
            }
        }
    }

    // MARK: - 加载与保存

    private func loadDraft() {
        guard !didLoad else { return }
        if let log = existingLog {
            selectedTags = Set(log.reasonTags)
            freeReason = log.freeReason
            dispositionPlan = log.dispositionPlan
        }
        didLoad = true
    }

    private func save() {
        let trimmedReason = freeReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlan = dispositionPlan.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = Array(selectedTags)

        if let log = existingLog {
            log.reasonTags = tags
            log.freeReason = trimmedReason
            log.dispositionPlan = trimmedPlan
            log.updatedAt = Date()
        } else {
            let log = AnomalyLog(
                date: normalizedDate,
                reasonTags: tags,
                freeReason: trimmedReason,
                dispositionPlan: trimmedPlan
            )
            modelContext.insert(log)
        }
        try? modelContext.save()
        dismiss()
    }

    private func delete() {
        if let log = existingLog {
            modelContext.delete(log)
            try? modelContext.save()
        }
        dismiss()
    }

    // MARK: - Helpers

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: d)
    }
}

// MARK: - 简单 Flow Layout（避免 LazyVGrid 在 chip 列表里强制等宽的问题）

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[(CGSize, Int)]] = [[]]
        var currentRowWidth: CGFloat = 0

        for (index, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let needsNewRow = currentRowWidth + (currentRowWidth > 0 ? spacing : 0) + size.width > maxWidth
            if needsNewRow && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentRowWidth = 0
            }
            rows[rows.count - 1].append((size, index))
            currentRowWidth += (currentRowWidth > 0 ? spacing : 0) + size.width
        }

        let height = rows.reduce(CGFloat(0)) { acc, row in
            let rowHeight = row.map(\.0.height).max() ?? 0
            return acc + rowHeight + (acc > 0 ? spacing : 0)
        }
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += currentRowHeight + spacing
                currentRowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
            _ = maxWidth
        }
    }
}
