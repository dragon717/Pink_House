import SwiftUI

// MARK: - 预览
#Preview {
    if #available(iOS 18.0, *) {
        PetChatView(searchText: .constant(""))
    } else {
        PetChatViewLegacy(searchText: .constant(""))
    }
}
