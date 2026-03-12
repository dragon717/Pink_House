
import SwiftUI
import SwiftData

struct OOTDView: View {
    var hideBackButton: Bool = false

    // 用于外部监听当前是否选中了书（书页列表模式下隐藏全局导航返回按钮）
    @Binding var isBookSelected: Bool

    // 用于外部监听当前是否选中了空间书（空间书页列表模式下隐藏全局导航返回按钮）
    @Binding var isSpaceBookSelected: Bool

    // 从魔法贴纸加入手帐后需要自动导航到的书
    @State private var navigateToBookID: UUID?

    var body: some View {
        BookShelfView(
            hideBackButton: hideBackButton,
            isBookSelected: $isBookSelected,
            isSpaceBookSelected: $isSpaceBookSelected,
            navigateToBookID: $navigateToBookID
        )
        .onReceive(NotificationCenter.default.publisher(for: .navigateToBookDetail)) { notification in
            // 监听从魔法贴纸加入手帐后的导航通知（第二次通知，确保视图已创建）
            if let bookID = notification.userInfo?["bookID"] as? UUID {
                navigateToBookID = bookID
            }
        }
    }
}

/*
// Legacy OOTDView for reference
struct LegacyOOTDView: View {
    // ...
}
*/
