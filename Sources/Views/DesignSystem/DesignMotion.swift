import SwiftUI

enum DesignMotion {
    static let press = Animation.easeOut(duration: 0.16)
    static let interaction = Animation.easeOut(duration: 0.16)
    static let emphasis = Animation.spring(duration: 0.3, bounce: 0)
    static let iconSwap = Animation.spring(duration: 0.3, bounce: 0)
}
