import SwiftUI

// MARK: - 时光馆下载缓存设置
//
// 对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §13.2。
//
// 界面必须如实说明清理范围：
//   仅清理**可重新下载**的图鉴资料与图片；
//   不会删除衣橱、手账、收藏或个人照片。

struct TimeHallCacheSettingsView: View {
    @StateObject private var model = TimeHallCacheSettingsModel()
    @State private var showingClearConfirmation = false
    @AppStorage(TimeHallRuntimeConfiguration.cloudSyncDefaultsKey)
    private var cloudSyncEnabled = false

    var body: some View {
        AdaptiveSettingsView(title: "时光馆下载缓存") {
            AdaptiveSection(
                header: "线上更新",
                footer: "关闭时只使用随包离线资料与本机已下载内容。运营发布首个线上版本后再打开此项；打开后会在启动时确认一次线上版本，版本未变则不会重复下载。"
            ) {
                Toggle(isOn: $cloudSyncEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("检查线上更新")
                        Text("从公共库确认运营发布的图鉴资料是否有更新")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .adaptiveRow(showDivider: false)
            }

            AdaptiveSection(header: "缓存占用") {
                usageRow(
                    title: "图鉴数据",
                    value: model.usage.packDescription,
                    systemImage: "square.stack.3d.up"
                )
                usageRow(
                    title: "图片缓存",
                    value: model.usage.mediaDescription,
                    systemImage: "photo.on.rectangle"
                )
                usageRow(
                    title: "最近检查",
                    value: model.lastCheckedDescription,
                    systemImage: "clock.arrow.circlepath"
                )
                usageRow(
                    title: "合计",
                    value: TimeHallCacheUsage.format(model.usage.totalBytes),
                    systemImage: "internaldrive",
                    showDivider: false
                )
            }

            AdaptiveSection(
                header: "清理",
                footer: "仅清理可重新下载的图鉴资料和图片。不会删除衣橱、手账、收藏或个人照片。清理后当前页面会退回随包离线资料，下次访问时按需重新下载。"
            ) {
                Button {
                    showingClearConfirmation = true
                } label: {
                    HStack {
                        Label("清理下载缓存", systemImage: "trash")
                        Spacer()
                        if model.isClearing {
                            ProgressView()
                        }
                    }
                }
                .disabled(model.isClearing || model.usage.downloadedBytes == 0)
                .adaptiveRow(showDivider: false)
            }

            if model.didClear {
                AdaptiveSection(footer: "下载缓存已清理，收藏与个人资料未受影响。") {
                    Label("清理完成", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .adaptiveRow(showDivider: false)
                }
            }
        }
        .task {
            await model.loadUsage()
        }
        .alert("清理下载缓存？", isPresented: $showingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                Task { await model.clear() }
            }
        } message: {
            Text("将删除可重新下载的图鉴资料与图片缓存，不会删除你的衣橱、手账、收藏或个人照片。")
        }
        .alert(
            "清理失败",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("确定", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func usageRow(
        title: String,
        value: String,
        systemImage: String,
        showDivider: Bool = true
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if model.isLoading {
                ProgressView()
            } else {
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .adaptiveRow(showDivider: showDivider)
    }
}
