import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 当前类型的颜色批量配图。分配先留在窗口工作副本，确认时按稳定 ID 写回。
struct OpsColorImagesSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let entry: OpsSeriesTypeEntry
    @Environment(\.dismiss) private var dismiss
    @State private var assignments: [String: String]
    @State private var selectedColorIDs: Set<String>
    @State private var searchText = ""
    @State private var uploadsOnly = true
    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var feedback: String?
    @State private var importFailures: [String] = []
    @State private var saveError: String?

    init(workspace: OpsWorkspace, entry: OpsSeriesTypeEntry, initialColorID: String? = nil) {
        self.workspace = workspace
        self.entry = entry
        _assignments = State(initialValue: Dictionary(uniqueKeysWithValues: entry.colors.compactMap {
            color in color.imageAssetID.map { (color.id, $0) }
        }))
        let selected = entry.colors.first { $0.id == initialColorID } ?? entry.colors.first
        _selectedColorIDs = State(initialValue: Set(selected.map { [$0.id] } ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("批量填充颜色图片 · \(entry.displayName)").font(.title3.weight(.semibold))
            Text("勾选右侧颜色，再点击左侧图片完成分配；可以为多个颜色使用同一张图。")
                .font(.callout).foregroundStyle(.secondary)
            HSplitView {
                imageLibrary.frame(minWidth: 450, maxWidth: .infinity)
                colorList.frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
            }
            .disabled(isImporting)
            if isImporting { ProgressView("正在导入图片…").controlSize(.small) }
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
            if !importFailures.isEmpty {
                ScrollView {
                    Text(importFailures.joined(separator: "\n"))
                        .font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 70)
            }
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("已上传图片保留在「上传历史」，关闭窗口或退出 App 后仍可复用；取消只放弃本次配图。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isImporting)
                Button("确定") {
                    if workspace.applyColorImages(
                        entryID: entry.id, colorIDs: Set(entry.colors.map(\.id)), assignments: assignments) {
                        dismiss()
                    } else {
                        saveError = workspace.lastError ?? "配图保存失败，请重试。"
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting || !workspace.canEdit)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 960, height: 650)
        .interactiveDismissDisabled(isImporting)
        .onAppear { workspace.loadImageUploadHistory() }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) {
            result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                isImporting = true
                Task { @MainActor in
                    let outcome = await workspace.importColorImages(from: urls)
                    importFailures = outcome.failures
                    if !outcome.assetIDs.isEmpty {
                        uploadsOnly = true
                        searchText = ""
                    }
                    feedback = "本次导入 \(outcome.assetIDs.count) 张图片。勾选右侧颜色后，点击图片分配。"
                    isImporting = false
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    importFailures = ["图片选择失败：\(error.localizedDescription)"]
                }
            }
        }
    }

    private var imageLibrary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("图片范围", selection: $uploadsOnly) {
                    Text("全部图片").tag(false)
                    Text("上传历史").tag(true)
                }
                .labelsHidden().frame(width: 125)
                TextField("搜索图片名称", text: $searchText).textFieldStyle(.roundedBorder)
                Button("本地上传（可多选）") { showsImporter = true }
            }
            ScrollView {
                if availableAssets.isEmpty {
                    VStack(spacing: 10) {
                        OpsImageUploadThumbnail(url: nil, size: 90, title: "点击批量上传颜色图片") {
                            showsImporter = true
                        }
                        Text(searchText.isEmpty ? "点击图片框上传多张图片" : "没有匹配的图片")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 70)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 12)], spacing: 14) {
                        ForEach(availableAssets) { asset in
                            imageTile(asset)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(.trailing, 12)
    }

    private var availableAssets: [OpsImageLibraryItem] {
        workspace.imageLibraryItems(uploadsOnly: uploadsOnly, search: searchText)
    }

    private func imageTile(_ item: OpsImageLibraryItem) -> some View {
        let assignedCount = assignments.values.filter { $0 == item.id }.count
        return Button {
            guard !selectedColorIDs.isEmpty else {
                feedback = "请先勾选右侧需要配图的颜色。"
                return
            }
            guard let assetID = workspace.useImageLibraryItem(item) else {
                saveError = workspace.lastError ?? "无法读取历史图片，请重试。"
                return
            }
            for colorID in selectedColorIDs { assignments[colorID] = assetID }
            feedback = "已为 \(selectedColorIDs.count) 个颜色分配图片，点击「确定」保存。"
            saveError = nil
        } label: {
            VStack(spacing: 5) {
                OpsThumbnail(url: item.fileURL, size: 104)
                Text(item.name).font(.caption).lineLimit(1).truncationMode(.middle)
                Text(assignedCount == 0 ? "点击分配" : "已分配 \(assignedCount) 个颜色")
                    .font(.caption2)
                    .foregroundStyle(assignedCount == 0 ? Color.secondary : Color.accentColor)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .background(assignedCount == 0 ? Color.clear : Color.accentColor.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("为勾选的颜色分配「\(item.name)」")
    }

    private var colorList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择颜色填充（已勾选 \(selectedColorIDs.count)）").font(.headline)
            HStack {
                Button("全选") { selectedColorIDs = Set(entry.colors.map(\.id)) }
                Button("清除选择") { selectedColorIDs = [] }
                Spacer()
            }
            .controlSize(.small)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(entry.colors) { color in
                        colorRow(color)
                    }
                }
            }
        }
        .padding(.leading, 12)
    }

    private func colorRow(_ color: OpsSeriesColorSKU) -> some View {
        let assetID = assignments[color.id]
        return HStack(spacing: 8) {
            Toggle("选择颜色", isOn: Binding(
                get: { selectedColorIDs.contains(color.id) },
                set: { if $0 { selectedColorIDs.insert(color.id) } else { selectedColorIDs.remove(color.id) } }))
                .labelsHidden().toggleStyle(.checkbox)
                .accessibilityLabel(Text("选择\(color.name.isEmpty ? "未命名颜色" : color.name)"))
            Button {
                selectedColorIDs = [color.id]
            } label: {
                HStack {
                    Text(color.name.isEmpty ? "未命名颜色" : color.name)
                        .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    OpsThumbnail(url: assetID.flatMap {
                        workspace.stagedFileURL(forReference: workspace.asset(for: $0)?.originalURL)
                    }, size: 44)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                assignments.removeValue(forKey: color.id)
                saveError = nil
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain).disabled(assetID == nil)
            .help("清除这个颜色的图片")
        }
        .padding(8)
        .background(selectedColorIDs.contains(color.id) ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}
