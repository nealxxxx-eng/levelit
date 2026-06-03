import SwiftUI
import LevelItShared

struct ShareCardView: View {
    @Environment(\.popToRoot) private var popToRoot
    let task: DebtTask
    @State private var cardImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                shareCardContent
                    .onAppear { renderCard() }

                VStack(spacing: DS.Spacing.md) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .font(.headline).frame(maxWidth: .infinity).padding()
                            .background(DS.Colors.accent).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    }

                    Button { saveToPhotos() } label: {
                        Label("保存图片", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding()
                            .background(DS.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    }

                    Button { popToRoot() } label: {
                        Label("返回首页", systemImage: "house.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding()
                            .background(DS.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("分享卡")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let image = cardImage {
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - Share Card Content

    @ViewBuilder
    private var shareCardContent: some View {
        let isOver = task.isOverAchieved
        let isSettled = task.status == .settled || task.status == .completed

        VStack(spacing: 0) {
            // 顶部渐变条
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: isOver ? [.orange, .yellow] : [.orange, .orange.opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 6)

            VStack(spacing: DS.Spacing.lg) {
                // 头部
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("磨平")
                            .font(.title3.weight(.bold))
                        Text(isOver ? "超额完成!" : isSettled ? "已结清" : "已磨平 \(task.progressPercent)%")
                            .font(.caption)
                            .foregroundStyle(isOver ? .orange : isSettled ? .green : .secondary)
                    }
                    Spacer()
                    // 运动类型图标
                    VStack(spacing: 2) {
                        Image(systemName: task.taskMode.iconName)
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text(task.taskMode.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                // 食物大图
                VStack(spacing: DS.Spacing.sm) {
                    Text(task.foodEmoji)
                        .font(.system(size: 72))
                    Text(task.foodName)
                        .font(.title2.weight(.bold))

                    if isOver {
                        Text("还多了 \(task.progressPercent - 100)%，下次可以白嗝一口")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)

                // 数据三栏
                HStack(spacing: 0) {
                    dataColumn(
                        value: "\(task.burnedCalories)",
                        unit: "kcal",
                        label: "消耗"
                    )
                    Rectangle().fill(.secondary.opacity(0.3)).frame(width: 1, height: 36)
                    dataColumn(
                        value: "\(task.progressPercent)%",
                        unit: nil,
                        label: "完成度",
                        highlight: isOver
                    )
                    Rectangle().fill(.secondary.opacity(0.3)).frame(width: 1, height: 36)
                    dataColumn(
                        value: formatDuration(task.durationSeconds),
                        unit: nil,
                        label: "用时"
                    )
                }
                .padding(.vertical, DS.Spacing.sm)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

                // 底部 slogan
                HStack(spacing: DS.Spacing.xs) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("拍一下你要吃的东西，看看你得动多久")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(DS.Spacing.lg)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }

    private func dataColumn(value: String, unit: String? = nil, label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundStyle(highlight ? .orange : .primary)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Render & Share

    @MainActor
    private func renderCard() {
        let renderer = ImageRenderer(content:
            shareCardContent
                .frame(width: 360)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3  // 高分辨率
        if let uiImage = renderer.uiImage {
            // 剥离 EXIF (重新编码为 PNG, 不含元数据)
            if let pngData = uiImage.pngData(),
               let cleanImage = UIImage(data: pngData) {
                cardImage = cleanImage
            } else {
                cardImage = uiImage
            }
        }
    }

    private func saveToPhotos() {
        guard let image = cardImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return "\(m)分\(s)秒"
        }
        return "\(s)秒"
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
