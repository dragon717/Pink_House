
import SwiftUI
import SwiftData

struct OOTDView: View {
    var hideBackButton: Bool = false
    
    // 用于外部监听当前是否选中了书（书页列表模式下隐藏全局导航返回按钮）
    @Binding var isBookSelected: Bool
    
    // 用于外部监听当前是否选中了空间书（空间书页列表模式下隐藏全局导航返回按钮）
    @Binding var isSpaceBookSelected: Bool
    
    var body: some View {
        BookShelfView(hideBackButton: hideBackButton, isBookSelected: $isBookSelected, isSpaceBookSelected: $isSpaceBookSelected)
    }
}

/*
// Legacy OOTDView for reference
struct LegacyOOTDView: View {
    // ...
}
*/
