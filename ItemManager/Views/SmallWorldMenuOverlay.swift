import SwiftUI

/// Compatibility namespace retained for existing guide fallback callers.
///
/// House long-press quick menu has been retired. The project file still keeps
/// this source path, so the remaining type only exposes the bottom-dock frame
/// helper used by guide overlays.
enum SmallWorldMenuOverlay {
    /// LegacyTabView self-drawn bottom dock fallback: full width minus horizontal
    /// padding, with the House segment following the user's current dock layout.
    static func buildFallbackFrame(
        screenSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat,
        isIPad: Bool,
        houseSlotIndex: Int = 1
    ) -> CGRect {
        _ = safeAreaTop
        _ = isIPad

        let tabBarHeight: CGFloat = 56
        let horizontalPadding: CGFloat = 16
        let bottomPadding: CGFloat = safeAreaBottom > 0 ? 2 : 4
        let tabBarY = screenSize.height - tabBarHeight - max(safeAreaBottom, 0) - bottomPadding
        let tabBarWidth = screenSize.width - horizontalPadding * 2
        let tabCount = CGFloat(TabBarItemAnchorResolver.mainTabCount)
        let segmentWidth = tabBarWidth / tabCount
        let clampedIndex = min(max(houseSlotIndex, 0), TabBarItemAnchorResolver.mainTabCount - 1)
        let tabX = horizontalPadding + segmentWidth * CGFloat(clampedIndex)
        return CGRect(x: tabX, y: tabBarY, width: segmentWidth, height: tabBarHeight)
    }
}
