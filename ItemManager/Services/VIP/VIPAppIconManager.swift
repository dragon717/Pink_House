import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct VIPAppIconOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let subtitle: String
    let previewAssetName: String
    let alternateIconName: String?
    let badgeText: String?
}

@MainActor
final class VIPAppIconManager: ObservableObject {
    static let shared = VIPAppIconManager()

    @Published private(set) var currentIconID: String = "primary"
    @Published private(set) var isApplying: Bool = false

    let availableIcons: [VIPAppIconOption] = [
        VIPAppIconOption(
            id: "primary",
            displayName: "少女心愿立体",
            subtitle: "经典衣橱主视觉，甜美又有辨识度",
            previewAssetName: "vip_icon_preview_logo",
            alternateIconName: nil,
            badgeText: "经典"
        ),
        VIPAppIconOption(
            id: "pink_wish",
            displayName: "心愿礼服馆",
            subtitle: "粉色礼服馆风格，把少女心放上桌面",
            previewAssetName: "vip_icon_preview_pink_wish",
            alternateIconName: "VIPIconPinkWish",
            badgeText: "VIP专属"
        ),
        VIPAppIconOption(
            id: "dream_closet",
            displayName: "珍珠衣柜",
            subtitle: "立体珍珠衣柜风格，温柔精致",
            previewAssetName: "vip_icon_preview_dream_closet",
            alternateIconName: "VIPIconDreamCloset",
            badgeText: "VIP专属"
        ),
        VIPAppIconOption(
            id: "pearl_wardrobe",
            displayName: "珍珠礼服柜",
            subtitle: "粉金珍藏款，像一只小小的礼服收藏柜",
            previewAssetName: "vip_icon_preview_pearl_wardrobe",
            alternateIconName: "VIPIconPearlWardrobe",
            badgeText: "珍藏款"
        ),
        VIPAppIconOption(
            id: "moon_wardrobe",
            displayName: "月光玻璃柜",
            subtitle: "月光琉璃款，清透安静的夜色衣橱",
            previewAssetName: "vip_icon_preview_moon_wardrobe",
            alternateIconName: "VIPIconMoonWardrobe",
            badgeText: "月光款"
        )
    ]

    private init() {
        refreshCurrentIcon()
    }

    var currentOption: VIPAppIconOption {
        availableIcons.first(where: { $0.id == currentIconID }) ?? availableIcons[0]
    }

    var supportsAlternateIcons: Bool {
#if canImport(UIKit)
        UIApplication.shared.supportsAlternateIcons
#else
        false
#endif
    }

    func refreshCurrentIcon() {
        currentIconID = availableIcons.first(where: { $0.alternateIconName == currentAlternateIconName })?.id ?? "primary"
    }

    func applyIcon(_ option: VIPAppIconOption) async -> (success: Bool, message: String) {
        guard VIPManager.shared.isVIP else {
            return (false, "开通 VIP 后，就可以为桌面换上专属图标。")
        }

        guard supportsAlternateIcons else {
            return (false, "这台设备暂时不能切换桌面图标。")
        }

        guard currentIconID != option.id else {
            return (true, "你已经在使用「\(option.displayName)」了。")
        }

        isApplying = true
        defer { isApplying = false }

#if canImport(UIKit)
        do {
            try await setAlternateIconName(option.alternateIconName)
            refreshCurrentIcon()
            return (true, "已切换为「\(option.displayName)」。")
        } catch {
            return (false, errorMessage(for: error, option: option))
        }
#else
        return (false, "现在暂时不能切换桌面图标。")
#endif
    }

    private var currentAlternateIconName: String? {
#if canImport(UIKit)
        UIApplication.shared.alternateIconName
#else
        nil
#endif
    }

#if canImport(UIKit)
    private func setAlternateIconName(_ iconName: String?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UIApplication.shared.setAlternateIconName(iconName) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
#endif

    private func errorMessage(for error: Error, option: VIPAppIconOption) -> String {
        "暂时没能换成「\(option.displayName)」，可以稍后再试。"
    }
}
