import Foundation

enum DesignRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 14

    static func inner(of outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, outer - padding)
    }
}
