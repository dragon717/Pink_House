
import SwiftUI
import SwiftData

struct OOTDView: View {
    var hideBackButton: Bool = false
    
    var body: some View {
        BookShelfView(hideBackButton: hideBackButton)
    }
}

/*
// Legacy OOTDView for reference
struct LegacyOOTDView: View {
    // ...
}
*/
