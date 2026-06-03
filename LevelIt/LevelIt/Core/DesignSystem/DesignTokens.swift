import SwiftUI

/// 设计系统 token
enum DS {
    // MARK: - Colors
    enum Colors {
        static let background = Color(.systemBackground)
        static let cardBackground = Color(.secondarySystemBackground)
        static let accent = Color.orange
        static let success = Color.green
        static let warning = Color.orange
        static let danger = Color.red
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }
}
