import SwiftUI

/// 使用当前窗口的可用空间，而非设备型号或屏幕方向。
enum DetailImageLayout {
    static func height(in size: CGSize) -> CGFloat {
        let availableHeight = max(1, size.height)
        let preferredHeight: CGFloat = size.width > availableHeight ? availableHeight * 0.7 : 400
        return max(1, min(preferredHeight, availableHeight * 0.7))
    }
}
