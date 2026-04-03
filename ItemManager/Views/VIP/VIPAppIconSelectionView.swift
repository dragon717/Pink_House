import SwiftUI

struct VIPAppIconSelectionView: View {
    @ObservedObject private var vipManager = VIPManager.shared
    @ObservedObject private var iconManager = VIPAppIconManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var resultMessage = ""
    @State private var showingResultAlert = false

    private var visualTheme: VIPVisualTheme {
        vipManager.preferredVisualTheme
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: visualTheme.backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(visualTheme.glowColor)
                .frame(width: 260, height: 260)
                .blur(radius: 56)
                .offset(x: -100, y: -220)

            Circle()
                .fill(visualTheme.glowColor.opacity(0.7))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 120, y: -60)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    topBar
                    introCard
                    supportCard

                    VStack(spacing: 14) {
                        ForEach(iconManager.availableIcons) { option in
                            iconOptionCard(option)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            iconManager.refreshCurrentIcon()
        }
        .alert("个性图标", isPresented: $showingResultAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(resultMessage)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("个性图标库")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("VIP 可自主切换应用图标")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(visualTheme.secondaryTextColor)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                ZStack {
                    VIPGlassCardBackground(glassStyle: visualTheme.secondaryGlassStyle, cornerRadius: 18)
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
        }
    }

    private var introCard: some View {
        ZStack {
            VIPGlassCardBackground(glassStyle: visualTheme.primaryGlassStyle, cornerRadius: 26)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(visualTheme.primaryGlassStyle.iconTint)
                    Text("让 VIP 身份延伸到桌面")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("图标切换采用和 VIP 页同源的黑玻璃视觉语言。当前已接入「少女心愿立体」与「经典图标」两套方案，后续继续往图标库里扩。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private var supportCard: some View {
        HStack(spacing: 12) {
            Image(systemName: iconManager.supportsAlternateIcons ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(iconManager.supportsAlternateIcons ? visualTheme.accentColor : Color.orange)

            Text(iconManager.supportsAlternateIcons ? "当前设备支持应用图标切换。" : "当前设备暂不支持应用图标切换，可先保留这套图标库设计。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()
        }
        .padding(16)
        .background(VIPGlassCardBackground(glassStyle: .glossBlack, cornerRadius: 22))
    }

    private func iconOptionCard(_ option: VIPAppIconOption) -> some View {
        let isCurrent = iconManager.currentIconID == option.id

        return HStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 92, height: 92)

                Image(option.previewAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(4)

                if let badgeText = option.badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(visualTheme.accentColor.opacity(0.28)))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .offset(x: 8, y: -8)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(option.displayName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)

                    if isCurrent {
                        Text("当前使用")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(visualTheme.accentColor))
                    }
                }

                Text(option.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task {
                        let result = await iconManager.applyIcon(option)
                        resultMessage = result.message
                        showingResultAlert = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if iconManager.isApplying && !isCurrent {
                            ProgressView()
                                .tint(Color.black.opacity(0.9))
                        }
                        Text(isCurrent ? "已启用" : "切换图标")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(iconManager.supportsAlternateIcons ? visualTheme.accentColor : Color.white.opacity(0.35))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCurrent || iconManager.isApplying || !iconManager.supportsAlternateIcons || !vipManager.isVIP)
            }

            Spacer()
        }
        .padding(18)
        .background(
            VIPGlassCardBackground(
                glassStyle: isCurrent ? visualTheme.primaryGlassStyle : .glossBlack,
                cornerRadius: 24
            )
        )
    }
}

#Preview {
    VIPAppIconSelectionView()
}
