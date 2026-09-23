import SwiftUI
import SwiftData

// MARK: - 时光馆 Tab 壳层
//
// 2026-09-24：旧馆（编年史/图鉴/珍选/搭配 + 「我的品牌」品牌列表，即馆藏档案）
// 已整体移除，收藏 → 心愿迁移完成历史使命后一并下线；
// 时光馆首屏 = 店家上新（ShopCatalogBrowseView），不再有次级入口。
struct TimeHallView: View {
  @Environment(\.isRoutePageActive) private var isRoutePageActive

  var body: some View {
    ShopCatalogBrowseView()
  }
}
