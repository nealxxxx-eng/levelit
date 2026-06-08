import SwiftUI
import LevelItShared

struct PKChallengeEditView: View {
    var challenge: PKChallenge
    var onSave: (PKChallenge) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var targetCalories: Double
    @State private var durationDays: Double
    @State private var note: String
    @State private var expiresInHours: Double

    init(challenge: PKChallenge, onSave: @escaping (PKChallenge) -> Void) {
        self.challenge = challenge
        self.onSave = onSave
        _title = State(initialValue: challenge.title)
        _targetCalories = State(initialValue: Double(challenge.targetCalories))
        _durationDays = State(initialValue: Double(challenge.durationDays))
        _note = State(initialValue: challenge.note ?? "")
        let remaining = max(1, challenge.expiresAt.timeIntervalSince(Date()) / 3600)
        _expiresInHours = State(initialValue: min(Double(remaining), 72))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("挑战名称") {
                    TextField("标题", text: $title)
                }

                if challenge.type == .streakSprint {
                    Section {
                        sliderRow(
                            label: "连续天数",
                            value: $durationDays,
                            range: 1...14,
                            step: 1,
                            display: "\(Int(durationDays)) 天"
                        )
                    } header: { Text("目标") }
                } else {
                    Section {
                        sliderRow(
                            label: "目标消耗",
                            value: $targetCalories,
                            range: 50...1200,
                            step: 10,
                            display: "\(Int(targetCalories)) kcal"
                        )
                    } header: { Text("目标") }
                }

                Section {
                    sliderRow(
                        label: "有效期",
                        value: $expiresInHours,
                        range: 1...72,
                        step: 1,
                        display: expiryDisplay
                    )
                } header: {
                    Text("邀请有效期")
                } footer: {
                    Text("超时未被认领，挑战自动标记为已过期。")
                }

                Section("备注（可选）") {
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle("编辑挑战")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    // MARK: - Helpers

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var expiryDisplay: String {
        let h = Int(expiresInHours)
        if h < 24 { return "\(h) 小时" }
        let d = h / 24
        let rem = h % 24
        return rem == 0 ? "\(d) 天" : "\(d) 天 \(rem) 小时"
    }

    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text(label)
                Spacer()
                Text(display)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Colors.accent)
            }
            Slider(value: value, in: range, step: step)
                .tint(DS.Colors.accent)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func save() {
        challenge.title = trimmedTitle
        challenge.targetCalories = Int(targetCalories)
        challenge.durationDays = Int(durationDays)
        challenge.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        challenge.expiresAt = Date().addingTimeInterval(expiresInHours * 3600)
        onSave(challenge)
        dismiss()
    }
}
