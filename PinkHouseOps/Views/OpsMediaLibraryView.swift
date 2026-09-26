//
//  OpsMediaLibraryView.swift
//  PinkHouseOps
//
//  图片与上传任务台账。
//
//  ## 这里要回答的三个问题（三个互相独立的事实）
//
//  1. **目录 JSON 引用了哪些图？**（→ 发布门禁的 `requiredStagedFileNames`）
//  2. **staging 目录里实际有哪些文件？**
//  3. **台账里有哪些任务、各自什么状态？**
//
//  这三者会不一致，而且**每一种不一致都有不同的处置**：
//
//  | 现象 | 说明 | 处置 |
//  |---|---|---|
//  | 台账有、文件没有 | 别人手删过 staging / 换过机器 | 重新导入该图 |
//  | 文件有、台账没有 | 直接往 staging 里拷了图（没走导入） | 「补记素材」建台账 |
//  | 目录引用了不存在的文件 | 发布出去就是空图 | 「发布前校验」会阻断 |
//
//  所以本页把三者**分别列出来**，不用一个「共 N 张」的汇总数把它们糊在一起。
//
//  ## P1 不做真实上传
//
//  按计划的分期，P1 的交付是「本机草稿 + 离线校验 + 待发布包」；
//  真正写公共库是 P2（复用 `tools/time_hall/publication` 的发布器，
//  私钥只在 Keychain）。所以本页**不给「上传」按钮** ——
//  给一个点了不会有任何网络请求的按钮，比没有按钮更糟。
//  任务状态机（`MediaUploadJobMachine`）先按 `staged` 记账，
//  等 P2 接上发布器后由它推进。
//

import SwiftUI
import UniformTypeIdentifiers

struct OpsMediaLibraryView: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var selectedMediaKey: String?
    @State private var showsImageImporter = false

    /// 与概览页同源的白名单（`ShopCatalogSyncProtocol.mediaMimeAllowlist`）：
    /// 不放宽到 `.image` —— 客户端解不出来的类型不该走到发布这一步。
    private var importableImageTypes: [UTType] {
        var types: [UTType] = [.jpeg, .png, .gif]
        if let webp = UTType("org.webmproject.webp") { types.append(webp) }
        if let heic = UTType("public.heic") { types.append(heic) }
        return types
    }

    private var jobs: [MediaUploadJob] {
        workspace.mediaJobs.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                assetsCard
                progressCard
                jobsCard
                orphansCard
                missingCard
                pipelineNoteCard
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(
            isPresented: $showsImageImporter,
            allowedContentTypes: importableImageTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                workspace.importImages(from: urls)
            case .failure(let error):
                workspace.reportFailure("选择图片失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: 素材（可视化）

    /// 为什么要有这一块：之前素材只有「assetID + 状态」两列文字，
    /// 运营要自己去认 hash 才能知道哪张是哪张，结果是**图都在、但没人敢删**。
    /// 现在每张图直接显示缩略图、源文件名与「被谁引用」——
    /// 删之前能一眼看出会影响谁。
    private var assetsCard: some View {
        let assets = workspace.catalog.assets
        return OpsCard(title: "素材（\(assets.count)）", systemImage: "photo.on.rectangle.angled") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        showsImageImporter = true
                    } label: {
                        Label("导入商品图", systemImage: "photo.badge.plus")
                    }
                    .controlSize(.small)
                    OpsFootnote(text: "导入会立刻按「长边 1600」重新编码、算出内容摘要（mediaKey），"
                                + "并复制进本机暂存目录 —— 之后与原始位置无关。")
                }
                if assets.isEmpty {
                    Text("素材库是空的。导入商品图之后，才谈得上「绑到商品上」。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 168), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(assets) { asset in
                            assetCell(asset)
                        }
                    }
                }
            }
        }
    }

    private func assetCell(_ asset: CatalogAsset) -> some View {
        let refs = workspace.references(toAsset: asset.id)
        return VStack(alignment: .leading, spacing: 6) {
            OpsThumbnail(url: thumbnailURL(asset), size: 152)
            Text(fileLabel(asset)).font(.caption).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 6) {
                Text("\(asset.width ?? 0)×\(asset.height ?? 0)")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 2)
                OpsTag(text: refs.isEmpty ? "无人引用" : "被引 \(refs.count)",
                       tint: refs.isEmpty ? .orange : .accentColor)
            }
            if refs.isEmpty {
                OpsFootnote(text: "没有任何地方引用它 —— 发布时不会上传，可以安全移除。")
            } else {
                OpsFootnote(text: refs.prefix(2).map(\.owner).joined(separator: "；")
                            + (refs.count > 2 ? " 等 \(refs.count) 处" : ""))
            }
            Button(role: .destructive) {
                workspace.removeAsset(id: asset.id)
            } label: {
                Label("移除素材", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.link)
            .help(refs.isEmpty
                  ? "这张图没有任何引用，移除不会影响任何内容"
                  : "还有 \(refs.count) 处引用它，移除会被拒绝并列出引用者")
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1))
    }

    private func thumbnailURL(_ asset: CatalogAsset) -> URL? {
        workspace.stagedFileURL(forReference: asset.originalURL)
            ?? workspace.stagedFileURL(forReference: asset.previewURL)
            ?? workspace.stagedFileURL(forReference: asset.thumbnailURL)
    }

    /// 优先显示**源文件名** —— 运营认文件名，不认内容 hash
    private func fileLabel(_ asset: CatalogAsset) -> String {
        if let url = thumbnailURL(asset) { return url.lastPathComponent }
        return asset.originalURL.replacingOccurrences(of: "local:", with: "")
    }

    // MARK: 进度

    private var progressCard: some View {
        let progress = workspace.mediaProgress
        return OpsCard(title: "上传任务进度", systemImage: "arrow.up.circle") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(
                        [("全部", progress.total), ("已上传", progress.verified),
                         ("待处理", progress.pending), ("失败", progress.failed)],
                        id: \.0
                    ) { item in
                        VStack(spacing: 2) {
                            Text("\(item.1)").font(.title3.weight(.semibold)).monospacedDigit()
                            Text(item.0).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        workspace.rescanStagingDirectory()
                    } label: {
                        Label("补记素材（扫暂存目录）", systemImage: "arrow.clockwise")
                    }
                    Text("把「目录里有文件、台账没记录」的图片补进台账。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 任务列表

    private var jobsCard: some View {
        OpsCard(title: "任务清单", systemImage: "list.bullet") {
            if jobs.isEmpty {
                Text("台账是空的。到「概览」导入商品图，或点上面的「补记素材」。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    jobHeader
                    Divider()
                    ForEach(jobs) { job in
                        jobRow(job)
                        Divider()
                    }
                }
            }
        }
    }

    private var jobHeader: some View {
        HStack(spacing: 10) {
            Text("文件").frame(maxWidth: .infinity, alignment: .leading)
            Text("大小").frame(width: 74, alignment: .trailing)
            Text("类型").frame(width: 84, alignment: .leading)
            Text("状态").frame(width: 62, alignment: .leading)
            Text("文件在").frame(width: 52, alignment: .center)
            Text("").frame(width: 62)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    private func jobRow(_ job: MediaUploadJob) -> some View {
        let fileExists = workspace.stagedFileNames.contains(job.stagedFileName)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.stagedFileName)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(String(job.mediaKey.prefix(16)) + "…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(byteText(job.byteCount))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 74, alignment: .trailing)

                Text(job.mimeType.replacingOccurrences(of: "image/", with: ""))
                    .font(.caption)
                    .frame(width: 84, alignment: .leading)

                Text(job.state.displayName)
                    .font(.caption)
                    .foregroundStyle(color(for: job.state))
                    .frame(width: 62, alignment: .leading)

                Image(systemName: fileExists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(fileExists ? Color.green : Color.orange)
                    .help(fileExists ? "暂存目录里有这个文件" : "暂存目录里没有这个文件")
                    .frame(width: 52)

                Button("移除") {
                    workspace.removeMediaJob(mediaKey: job.mediaKey)
                }
                .buttonStyle(.link)
                .font(.caption)
                .frame(width: 62)
            }

            if let kind = job.failureKind {
                // ⚠️ `guidance` 是变量（住共享包 `ShopCatalogMediaJob` 里）。
                // 今天它的四种取值都没有 `**`，所以这一处**目前没坏** ——
                // 但同一条路径上的兄弟字段（`ShopCatalogStrictPolicy.guidance`、
                // `ShopCatalogBaselineVerdict.guidance`）都带星号，改文案的人一改就踩。
                // 用 `Label { } icon: { }` 才能把 `Text` 换成 opsMarkdown 的结果。
                Label {
                    opsMarkdown(kind.guidance)
                } icon: {
                    Image(systemName: "info.circle")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = job.lastErrorMessage {
                opsMarkdown(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 7)
        .contextMenu {
            Button("移除这条任务记录") { workspace.removeMediaJob(mediaKey: job.mediaKey) }
        }
    }

    private func color(for state: MediaUploadJobState) -> Color {
        switch state {
        case .verified: return .green
        case .failed: return .red
        case .retryable: return .orange
        case .uploading: return .accentColor
        case .staged: return .secondary
        }
    }

    // MARK: 孤儿素材

    private var orphansCard: some View {
        let orphans = workspace.orphanStagedFileNames
        return OpsCard(title: "只在暂存目录里的文件", systemImage: "questionmark.folder") {
            VStack(alignment: .leading, spacing: 8) {
                if orphans.isEmpty {
                    Text("没有孤儿文件：暂存目录里的每个文件都在台账里。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("这 \(orphans.count) 个文件在暂存目录里，但台账里没有记录 —— "
                         + "通常是直接往目录里拷了图，或者手工改过文件名。")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(orphans, id: \.self) { name in
                        Text(name).font(.caption).monospaced().lineLimit(1).truncationMode(.middle)
                    }
                    Button("补记到台账") { workspace.rescanStagingDirectory() }
                }
            }
        }
    }

    // MARK: 台账有、文件没了

    private var missingCard: some View {
        let missingKeys = workspace.mediaKeysMissingStagedFile
        return OpsCard(title: "台账有、文件已不在", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 8) {
                if missingKeys.isEmpty {
                    Text("台账里的每个任务都能在暂存目录里找到对应文件。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("有 \(missingKeys.count) 条任务的文件已经不在暂存目录里了。"
                         + "这些图如果还被目录引用着，发布会被拦下；请重新导入。")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(missingKeys, id: \.self) { key in
                        Text(String(key.prefix(24)) + "…")
                            .font(.caption).monospaced().lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: 流水线说明

    private var pipelineNoteCard: some View {
        OpsCard(title: "本页为什么不提供「上传」按钮", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 8) {
                Text("本工具（P1）只做本机草稿、离线校验和待发布包。"
                     + "真正写公共库由受控发布流水线完成：")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("python3 tools/time_hall/publication/build_release.py --shop-catalog-archive <待发布包> …")
                    .font(.caption)
                    .monospaced()
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                Text("签名私钥只存在于 Keychain，不进 App、不进日志；"
                     + "任务状态机（staged → uploading → verified）留在这里，等流水线接上后由它推进。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
