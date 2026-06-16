import SwiftUI

struct WealthHapticsSettingsView: View {
    @ObservedObject private var hapticManager = HapticEngineManager.shared

    var body: some View {
        AdaptiveSettingsView(title: WealthExperienceCopy.Settings.pageTitle) {
            AdaptiveSection(header: "个性化") {
                NavigationLink(destination: WealthCustomizationView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.purple)
                            .frame(width: 24)

                        VStack(alignment: .leading) {
                            Text(WealthExperienceCopy.Settings.paperStyleTitle.appLocalized)
                                .foregroundStyle(.primary)
                            Text(WealthExperienceCopy.Settings.paperStyleDescription.appLocalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .adaptiveRow()
            }

            AdaptiveSection(header: "触感反馈") {
                Toggle(isOn: $hapticManager.isHapticsEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .foregroundStyle(.brown)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("金豆银珠震动".appLocalized)
                                .foregroundStyle(.primary)
                            Text("控制金豆滚动、碰撞的震动反馈".appLocalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .adaptiveRow()
            }

            AdaptiveSection(header: "系统设置", footer: "如果应用内开启后仍无震动，请检查：\n1. 系统设置 > 声音与触感 > 系统触感反馈 是否开启\n2. 手机是否处于静音模式（部分震动在静音下可能不工作）") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    HStack {
                        Image(systemName: "gear").foregroundStyle(.blue)
                        Text("前往系统设置".appLocalized)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app").font(.caption).foregroundStyle(.gray)
                    }
                }
                .adaptiveRow(showDivider: false)
            }
        }
    }
}
