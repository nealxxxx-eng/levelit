import SwiftUI

/// 结清动画 — 食物卡被"磨平"消失, 替换为"已结清"
struct SettledAnimationView: View {
    let foodEmoji: String
    let foodName: String
    let onFinished: () -> Void

    @State private var foodScale: CGFloat = 1.0
    @State private var foodOpacity: Double = 1.0
    @State private var showSettled = false
    @State private var confettiTrigger = false

    var body: some View {
        ZStack {
            // 食物卡被磨平
            if !showSettled {
                VStack(spacing: 12) {
                    Text(foodEmoji)
                        .font(.system(size: 100))
                    Text(foodName)
                        .font(.title2.weight(.bold))
                }
                .scaleEffect(x: 1.0, y: foodScale)
                .opacity(foodOpacity)
            }

            // 结清状态
            if showSettled {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: confettiTrigger)

                    Text("已结清")
                        .font(.system(size: 36, weight: .bold, design: .rounded))

                    Text("这口没有赖账")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            runAnimation()
        }
    }

    private func runAnimation() {
        // Phase 1: 食物被压扁
        withAnimation(.spring(duration: 0.8)) {
            foodScale = 0.05
            foodOpacity = 0.0
        }

        // Phase 2: 显示结清
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                showSettled = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                confettiTrigger = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onFinished()
            }
        }
    }
}
