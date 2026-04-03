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

    static let classicAlternateIconName = "ClassicAppIcon"

    @Published private(set) var currentIconID: String = "primary"
    @Published private(set) var isApplying: Bool = false

    let availableIcons: [VIPAppIconOption] = [
        VIPAppIconOption(
            id: "primary",
            displayName: "少女心愿立体",
            subtitle: "来自 2026-03-05 的立体 logo 方案",
            previewAssetName: "vip_icon_preview_logo",
            alternateIconName: nil,
            badgeText: "当前主图标"
        ),
        VIPAppIconOption(
            id: "classic",
            displayName: "经典图标",
            subtitle: "保留旧版经典封面感图标",
            previewAssetName: "vip_icon_preview_classic",
            alternateIconName: "ClassicAppIcon",
            badgeText: "VIP 专属"
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
            return (false, "开通 VIP 后才能切换个性图标。")
        }

        guard supportsAlternateIcons else {
            return (false, "当前设备暂不支持应用图标切换。")
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
        return (false, "当前平台暂不支持应用图标切换。")
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
        "切换到「\(option.displayName)」失败了：\(error.localizedDescription)"
    }
}
