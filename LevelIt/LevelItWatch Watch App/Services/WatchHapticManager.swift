import WatchKit

/// Watch 触觉反馈管理器
/// 进度节点: 25% / 50% / 75% / 100% 各触发不同 Haptic
enum WatchHapticManager {

    private static let thresholds = [25, 50, 75, 100]

    /// 检查进度变化是否跨越了 Haptic 节点, 如果是则触发
    static func checkAndPlay(oldPercent: Int, newPercent: Int) {
        let triggered = thresholds.filter { oldPercent < $0 && newPercent >= $0 }
        for threshold in triggered {
            play(for: threshold)
        }
    }

    /// 按节点播放对应 Haptic
    static func play(for threshold: Int) {
        let device = WKInterfaceDevice.current()
        switch threshold {
        case 25:
            device.play(.notification)
        case 50:
            device.play(.directionUp)
        case 75:
            device.play(.success)
        case 100:
            // 胜利序列
            device.play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                device.play(.success)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                device.play(.notification)
            }
        default:
            break
        }
    }

    /// 通用反馈
    static func tap() {
        WKInterfaceDevice.current().play(.click)
    }

    static func failure() {
        WKInterfaceDevice.current().play(.failure)
    }
}
