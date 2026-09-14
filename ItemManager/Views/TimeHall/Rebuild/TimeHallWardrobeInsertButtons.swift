import SwiftUI

// MARK: - 加入衣橱：两种形态并列
//
// 使用者要求「两种形态都先做出来供对比，不要替我直接选定其中一种」，
// 所以这里**同时**渲染两个入口，视觉权重刻意做成对等（一个实心、一个描边，
// 谁也不比谁更「默认」），并在下方给出一行说明解释两者差别。

struct TimeHallWardrobeInsertButtons: View {
  var isBusy = false
  let onQuickInsert: () -> Void
  let onOpenEditor: () -> Void
  /// 可选的访问性标识前缀。
  ///
  /// 为什么需要：详情页弹在列表**之上**时，背后列表卡片上的同名按钮仍在层级里，
  /// `app.buttons["一键入库"]` 会命中多个元素而直接报
  /// 「Multiple matching elements found」。给详情页这一组加前缀后，
  /// UI 测试就能精确定位到「详情页那一颗」。（见 MidsummerSpecSelectionUITests）
  var identifierPrefix: String? = nil

  private func identifier(_ suffix: String) -> String {
    guard let identifierPrefix else { return suffix }
    return "\(identifierPrefix)-\(suffix)"
  }

  var body: some View {
    VStack(spacing: 7) {
      HStack(spacing: 10) {
        Button(action: onQuickInsert) {
          Label(
            isBusy ? "正在准备图片…".appLocalized : TimeHallWardrobeInsertMode.quickInsert.title,
            systemImage: isBusy
              ? "hourglass" : TimeHallWardrobeInsertMode.quickInsert.symbolName
          )
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.pink)
        .disabled(isBusy)
        .accessibilityIdentifier(identifier("quick-insert"))
        .accessibilityHint(TimeHallWardrobeInsertMode.quickInsert.hint)

        Button(action: onOpenEditor) {
          Label(
            TimeHallWardrobeInsertMode.openEditor.title,
            systemImage: TimeHallWardrobeInsertMode.openEditor.symbolName
          )
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 11)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.pink)
        .disabled(isBusy)
        .accessibilityIdentifier(identifier("open-editor"))
        .accessibilityHint(TimeHallWardrobeInsertMode.openEditor.hint)
      }

      Text(
        "\(TimeHallWardrobeInsertMode.quickInsert.hint) · \(TimeHallWardrobeInsertMode.openEditor.hint)"
      )
      .font(.caption2)
      .multilineTextAlignment(.center)
      .foregroundStyle(.secondary)
    }
  }
}

// MARK: - 卡片上的紧凑入口（形态 A）
//
// 「每个商品上提供直接添加到衣橱的入口」——卡片本身要能一点即入橱，
// 所以这里只放形态 A 的图标按钮；形态 B 留在详情页，避免卡片上按钮过密。
//
// ⚠️ 当前**没有任何调用点**（`rg TimeHallWardrobeQuickInsertIconButton` 为空）。
// 卡片上的紧凑入口现在由 `TimeHallCatalogItemCard` / `TimeHallCommerceItemCard`
// 内部直接用 `Color.pink` 实底 + 白图标实现（`.overlay(alignment: .topLeading)`）。
// 保留本组件是因为它记录了「紧凑入口」应有的可访问性契约；但要按现状修好样式——
// 原来用的 `.ultraThinMaterial` 在浅色商品图上等于「白图标压白底」，正是
// 「看不到一键入库入口」那个反馈的成因。留一个已知会隐形的组件在这里迟早会被复制出去。

struct TimeHallWardrobeQuickInsertIconButton: View {
  var isBusy = false
  /// 已入库后换成对勾
  var didInsert = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(
        systemName: didInsert
          ? "checkmark.circle.fill"
          : (isBusy ? "hourglass" : TimeHallWardrobeInsertMode.quickInsert.symbolName)
      )
      .font(.footnote.weight(.bold))
      .foregroundStyle(.white)
      .padding(8)
      // 必须实底：浅色商品图上 `.ultraThinMaterial` ≈ 隐形
      .background(didInsert ? Color.pink : MidsummerInsertAccent.orange, in: Circle())
      .overlay { Circle().stroke(Color.white.opacity(0.9), lineWidth: 1) }
      .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
    }
    .buttonStyle(.plain)
    .disabled(isBusy)
    .accessibilityLabel(TimeHallWardrobeInsertMode.quickInsert.title)
    .accessibilityHint(TimeHallWardrobeInsertMode.quickInsert.hint)
  }
}

/// 紧凑入库入口的实底色。放在这里而不是各卡片里各写一遍，
/// 避免两处入口的观感再次走偏。
private enum MidsummerInsertAccent {
  static let orange = Color(red: 1.00, green: 0.42, blue: 0.00)
}
