import SwiftUI
import SwiftData

// MARK: - 时光馆 Tab 壳层（重构方案 Phase 4）
//
// 首屏 = 店家上新（ShopCatalogBrowseView）；旧四模式（编年史/图鉴/珍选/搭配）
// 已整体迁入 Views/TimeHall/Legacy/TimeHallLegacyArchiveView.swift，以
// 「馆藏档案」只读次级入口过渡保留——入口移除待迁移数据（含收藏 → 心愿）
// 经一个使用周期验证后执行，届时本文件同步移除 showsLegacyArchive 分支。
struct TimeHallView: View {
  @Environment(\.isRoutePageActive) private var isRoutePageActive
  @Environment(\.modelContext) private var modelContext
  @State private var showsLegacyArchive = false

  var body: some View {
    Group {
      if showsLegacyArchive {
        TimeHallLegacyArchiveView(onClose: { showsLegacyArchive = false })
          // 旧馆自带自绘头部，隐藏系统导航栏；限定作用域，避免连带隐藏首屏店家上新的导航栏
          .toolbar(.hidden, for: .navigationBar)
      } else {
        // 首屏 = 店家上新（V1.1 文档：时光馆 → 店家上新 → …）
        ShopCatalogBrowseView(onLegacyArchive: { showsLegacyArchive = true })
      }
    }
    .onChange(of: isRoutePageActive) { _, isActive in
      guard isActive else { return }
      showsLegacyArchive = false
    }
    .task {
      // 旧馆收藏 → 心愿尾款 一次性迁移（方案 §5.6；标记存在即静默跳过，
      // 未匹配收藏保留旧馆归档，treasured.v1 原键永不删除）
      TimeHallTreasuredWishMigrator.runIfNotYetMigrated(modelContext: modelContext)
    }
  }
}
