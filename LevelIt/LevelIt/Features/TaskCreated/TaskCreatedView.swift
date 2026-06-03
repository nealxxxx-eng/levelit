import SwiftUI
import LevelItShared

/// "已发送到手表"引导页 — 创建任务后引导用户去 Watch 开始运动
struct TaskCreatedView: View {
    @Environment(\.popToRoot) private var popToRoot
    let task: DebtTask

    @State private var showCheckmark = false
    @State private var showContent = false

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()

            // 成功动画
            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }

            // 任务信息
            if showContent {
                VStack(spacing: DS.Spacing.md) {
                    Text("任务已创建")
                        .font(.title2.weight(.bold))

                    // 食物卡片
                    VStack(spacing: DS.Spacing.sm) {
                        Text(task.foodEmoji)
                            .font(.system(size: 48))
                        Text(task.foodName)
                            .font(.headline)
                        Text("\(task.estimatedCalories) kcal · \(task.taskMode.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(DS.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))

                    // Watch 引导
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 36))
                            .foregroundStyle(DS.Colors.accent)

                        Text("抬手开始磨平")
                            .font(.headline)

                        Text("任务已同步到 Apple Watch")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()

            // 返回首页
            if showContent {
                Button {
                    popToRoot()
                } label: {
                    Text("返回首页")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DS.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                .transition(.opacity)
            }
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        withAnimation(.spring(duration: 0.5)) {
            showCheckmark = true
        }
        withAnimation(.spring(duration: 0.5).delay(0.5)) {
            showContent = true
        }
    }
}
