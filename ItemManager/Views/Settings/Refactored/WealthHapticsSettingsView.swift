import SwiftUI
import SwiftData

struct WealthHapticsSettingsView: View {
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var vipManager = VIPManager.shared
    @State private var appearanceManager = WealthAppearanceManager.shared
    @State private var showVIPRequiredAlert = false
    @State private var showVIPCenter = false
    
    var body: some View {
        AdaptiveSettingsView(title: WealthExperienceCopy.Settings.pageTitle) {
            // 0. 个性化设置
            AdaptiveSection(header: "个性化") {
                NavigationLink(destination: WealthCustomizationView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading) {
                            Text(WealthExperienceCopy.Settings.paperStyleTitle)
                                .foregroundStyle(.primary)
                            Text(WealthExperienceCopy.Settings.paperStyleDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .adaptiveRow()

                if vipManager.isVIP {
                    NavigationLink(destination: FinalPaymentVaultMascotSettingsView()) {
                        mascotSettingsRow(showLock: false)
                    }
                    .adaptiveRow(showDivider: false)
                } else {
                    Button {
                        showVIPRequiredAlert = true
                    } label: {
                        mascotSettingsRow(showLock: true)
                    }
                    .buttonStyle(.plain)
                    .adaptiveRow(showDivider: false)
                }
            }

            // 1. 金豆银珠震动 (原应用内触感)
            AdaptiveSection(header: "触感反馈") {
                Toggle(isOn: $hapticManager.isHapticsEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .foregroundStyle(.brown)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("金豆银珠震动")
                                .foregroundStyle(.primary)
                            Text("控制金豆滚动、碰撞的震动反馈")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .adaptiveRow()
            }
            
            // 2. 系统设置引导
            AdaptiveSection(header: "系统设置", footer: "如果应用内开启后仍无震动，请检查：\n1. 系统设置 > 声音与触感 > 系统触感反馈 是否开启\n2. 手机是否处于静音模式（部分震动在静音下可能不工作）") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "gear")
                            .foregroundStyle(.blue)
                        Text("前往系统设置")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .adaptiveRow(showDivider: false)
            }
        }
        .alert("VIP 专属权益", isPresented: $showVIPRequiredAlert) {
            Button("取消", role: .cancel) { }
            Button("去开通 VIP") {
                showVIPCenter = true
            }
        } message: {
            Text(WealthExperienceCopy.Settings.mascotLockedMessage)
        }
        .sheet(isPresented: $showVIPCenter) {
            NavigationStack {
                VIPCenterView()
            }
        }
    }

    private func mascotSettingsRow(showLock: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: appearanceManager.finalPaymentVaultMascot.symbolName)
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text(WealthExperienceCopy.Settings.mascotTitle)
                        .foregroundStyle(.primary)
                    if showLock {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(showLock ? "VIP 专属 · 当前：\(appearanceManager.finalPaymentVaultMascot.displayName)" : "当前：\(appearanceManager.finalPaymentVaultMascot.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct FinalPaymentVaultMascotSettingsView: View {
    @State private var appearanceManager = WealthAppearanceManager.shared

    var body: some View {
        AdaptiveSettingsView(title: WealthExperienceCopy.Settings.mascotTitle) {
            AdaptiveSection(
                header: "VIP 专属形象",
                footer: WealthExperienceCopy.Settings.mascotFooter
            ) {
                ForEach(FinalPaymentVaultMascot.allCases) { mascot in
                    Button {
                        appearanceManager.finalPaymentVaultMascot = mascot
                    } label: {
                        HStack(spacing: 12) {
                            FinalPaymentVaultMascotPreview(mascot: mascot)
                                .frame(width: 52, height: 52)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(mascot.displayName)
                                    .foregroundStyle(.primary)
                                Text(mascot.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if appearanceManager.finalPaymentVaultMascot == mascot {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .adaptiveRow(showDivider: mascot != .goldPig)
                }
            }
        }
    }
}

private struct FinalPaymentVaultMascotPreview: View {
    let mascot: FinalPaymentVaultMascot

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.18), Color.yellow.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            switch mascot {
            case .miniVault:
                mascotImageOrFallback(systemName: "lock.shield.fill", color: .orange)
            case .fortuneCat:
                mascotImageOrFallback(systemName: "cat.fill", color: .orange)
            case .piggyBank:
                mascotImageOrFallback(systemName: "banknote.fill", color: .pink)
            case .goldPig:
                mascotImageOrFallback(systemName: "yensign.circle.fill", color: .yellow)
            }
        }
    }

    @ViewBuilder
    private func mascotImageOrFallback(systemName: String, color: Color) -> some View {
        if let uiImage = UIImage(named: mascot.assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .padding(5)
        } else {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
        }
    }
}
