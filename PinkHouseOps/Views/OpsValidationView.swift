//
//  OpsValidationView.swift
//  PinkHouseOps
//
//  发布前校验（P1 的核心交付）+ 导出「待发布包」。
//
//  ## 为什么门禁必须在导出**之前**跑，而且必须能阻断
//
//  `local:<文件名>` 只在这台机器的沙盒里有效。原样发出去，别的设备解不出文件，
//  商品图一律变占位图 —— 而且**数据是好的、只有图是空的**，线上看起来像
//  「App 的 bug」而不是「发布漏了图」（2026-09-25 真实踩到过）。
//
//  所以这里的口径是：**能离线判定的事，绝不留给线上**。
//  校验不通过 → 导出按钮直接禁用，并逐条列出「哪个字段引用了哪个找不到的文件」。
//
//  ## 待发布包的布局
//
//      shop-catalog.json
//      images/<文件名>
//
//  与 iOS 端「整包导出」逐字一致，发布端同一条命令就能吃：
//      python3 tools/time_hall/publication/build_release.py \
//          --shop-catalog-archive <这个 tar> …
//  不要自创第二种布局（计划 §6 P4 明确警告过）。
//
//  ## 校验与导出的分工
//
//  · 本页 `review` = 「发之前，图都准备好了吗」；
//  · 发布器在改写完 `local:` → `thmedia:` 之后还会做**后置校验**
//    （`ShopCatalogPublicationGate.issuesInPublishedCatalog`）——
//    「发之后，产物真的远端化了吗」。两者都要有，否则「上传步骤被跳过」
//    这种 bug 会一路走到线上。后置校验跑在发布器里，不在本页。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OpsValidationView: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var showsExporter = false
    @State private var exportDocument = TarArchiveDocument(data: Data())
    @State private var exportFileName = "pink-house-待发布包.tar"

    private var review: ShopCatalogPublicationReview? { workspace.review }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                actionCard
                if let review {
                    conclusionCard(review)
                    structuralCard(review)
                    blockingCard(review)
                    warningCard(review)
                    requiredFilesCard(review)
                    findingsCard(review)
                } else {
                    OpsCard(title: "还没跑过校验", systemImage: "questionmark.circle") {
                        Text("点上面的「跑一次发布前校验」，本机会把目录里所有图片引用"
                             + "逐条解一遍，告诉你哪几条解不出图。全过程不联网。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                layoutCard
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: TarArchiveDocument.tarType,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success(let url):
                workspace.reportSuccess("已导出待发布包：\(url.lastPathComponent)")
            case .failure(let error):
                workspace.reportFailure("导出失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: 操作

    private var actionCard: some View {
        OpsCard(title: "动作", systemImage: "play.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        workspace.validate()
                    } label: {
                        Label("跑一次发布前校验", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        export()
                    } label: {
                        Label("导出待发布包（tar）", systemImage: "shippingbox")
                    }
                    .disabled(review?.isBlocked ?? true)

                    Button {
                        workspace.rescanStagingDirectory()
                        workspace.validate()
                    } label: {
                        Label("刷新素材后重跑", systemImage: "arrow.clockwise")
                    }
                }
                Text("· 校验只读本机目录，不联网、不写任何文件。\n"
                     + "· 导出按钮在校验通过前是灰的 —— 这是**故意**的，"
                     + "它替代了「先导出、发布时才发现缺图」的失败方式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func export() {
        guard let result = review else { return }
        guard !result.isBlocked else {
            workspace.reportFailure("校验未通过，不能导出：\(result.blockingIssues.count + result.catalogIssues.count) 条问题待处理。")
            return
        }
        do {
            exportDocument = TarArchiveDocument(data: try workspace.makePublicationArchive())
            exportFileName = exportName()
            showsExporter = true
            // 后置校验的**前置版本**：本地产物里不该再有任何 `local:` 之外的意外，
            // 但此刻 local: 是**正常**的（发布器负责改写）。这里只提示，不阻断。
        } catch {
            workspace.reportFailure(error.localizedDescription)
        }
    }

    private func exportName() -> String {
        let title = workspace.draft?.title ?? "catalog"
        let safe = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "\(safe).tar"
    }

    // MARK: 结论

    private func conclusionCard(_ review: ShopCatalogPublicationReview) -> some View {
        OpsCard(title: "结论", systemImage: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: review.isBlocked
                          ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .foregroundStyle(review.isBlocked ? Color.red : Color.green)
                    Text(review.summary).font(.headline)
                    Spacer()
                    Button("复制问题清单") { copyIssues(review) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Text("共判定 \(review.findings.count) 处图片引用；"
                     + "本机需准备 \(review.requiredStagedFileNames.count) 个图片文件；"
                     + "已远端化 \(review.remoteMediaKeys.count) 个媒体键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyIssues(_ review: ShopCatalogPublicationReview) {
        var lines: [String] = []
        if !review.catalogIssues.isEmpty {
            lines.append("【目录结构问题】")
            lines.append(contentsOf: review.catalogIssues)
        }
        if !review.blockingIssues.isEmpty {
            lines.append("【阻断项】")
            lines.append(contentsOf: review.blockingIssues)
        }
        if !review.warnings.isEmpty {
            lines.append("【提示】")
            lines.append(contentsOf: review.warnings)
        }
        let text = lines.isEmpty ? "校验通过，没有问题。" : lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        workspace.reportSuccess("问题清单已复制到剪贴板（\(lines.count) 行）")
    }

    // MARK: 分类明细

    private func structuralCard(_ review: ShopCatalogPublicationReview) -> some View {
        OpsCard(title: "目录结构问题（\(review.catalogIssues.count)）", systemImage: "square.stack.3d.up") {
            if review.catalogIssues.isEmpty {
                Text("结构与消费端校验同口径，没有问题。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                IssueList(items: review.catalogIssues, tint: .red, maxLines: nil)
            }
        }
    }

    private func blockingCard(_ review: ShopCatalogPublicationReview) -> some View {
        OpsCard(title: "阻断项（\(review.blockingIssues.count)）", systemImage: "hand.raised") {
            if review.blockingIssues.isEmpty {
                Text("没有解不出图的引用。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                IssueList(items: review.blockingIssues, tint: .red, maxLines: nil)
            }
        }
    }

    private func warningCard(_ review: ShopCatalogPublicationReview) -> some View {
        OpsCard(title: "提示（\(review.warnings.count)）", systemImage: "info.circle") {
            if review.warnings.isEmpty {
                Text("没有需要看一眼的引用。").font(.callout).foregroundStyle(.secondary)
            } else {
                IssueList(items: review.warnings, tint: .orange, maxLines: 3)
            }
        }
    }

    // MARK: 本机需准备的图片

    private func requiredFilesCard(_ review: ShopCatalogPublicationReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            OpsCard(title: "本机需准备的图片（\(review.requiredStagedFileNames.count)）",
                    systemImage: "photo.stack") {
                if review.requiredStagedFileNames.isEmpty {
                    Text("没有需要本机上传的图片（都已经远端化，或者本来就没图）。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    let present = workspace.stagedFileNames
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(review.requiredStagedFileNames, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: present.contains(name)
                                      ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(present.contains(name) ? Color.green : Color.red)
                                Text(name)
                                    .font(.caption)
                                    .monospaced()
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                byteTextIfAvailable(name)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func byteTextIfAvailable(_ name: String) -> some View {
        let url = workspace.stagingDirectory.appendingPathComponent(name)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = (attributes[.size] as? NSNumber)?.intValue {
            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: 引用明细

    private func findingsCard(_ review: ShopCatalogPublicationReview) -> some View {
        OpsCard(title: "引用明细（\(review.findings.count)）", systemImage: "list.bullet.indent") {
            if review.findings.isEmpty {
                Text("目录里没有任何图片引用。").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(review.findings.enumerated()), id: \.offset) { _, finding in
                        HStack(alignment: .top, spacing: 8) {
                            Text(resolutionLabel(finding.resolution))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(resolutionColor(finding.resolution).opacity(0.16), in: Capsule())
                                .foregroundStyle(resolutionColor(finding.resolution))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(finding.owner).font(.callout).lineLimit(1)
                                Text(finding.reference)
                                    .font(.caption2).monospaced()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 4)
                        }
                    }
                }
            }
        }
    }

    private func resolutionLabel(_ resolution: ShopCatalogReferenceResolution) -> String {
        switch resolution {
        case .remoteMedia: return "已远端化"
        case .canonicalMediaKey: return "媒体键"
        case .stagedLocal: return "本机待上传"
        case .missingLocal: return "缺文件"
        case .bundled: return "App 内置"
        case .remoteURL: return "外链图"
        case .danglingAssetID: return "悬空引用"
        case .unverifiableBareName: return "裸名字"
        }
    }

    private func resolutionColor(_ resolution: ShopCatalogReferenceResolution) -> Color {
        if resolution.blocksPublication { return .red }
        if resolution.isWarning { return .orange }
        return .green
    }

    // MARK: 布局说明

    private var layoutCard: some View {
        OpsCard(title: "待发布包里有什么", systemImage: "shippingbox") {
            VStack(alignment: .leading, spacing: 8) {
                Text("shop-catalog.json\nimages/<文件名>")
                    .font(.caption)
                    .monospaced()
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                Text("与 iOS 端整包导出逐字一致，发布器同一条命令即可消费；"
                     + "本页不写公共库，也不接触签名私钥。")
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

// MARK: - 问题清单

private struct IssueList: View {
    let items: [String]
    let tint: Color
    let maxLines: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(tint)
                        .padding(.top, 6)
                    Text(item)
                        .font(.callout)
                        .lineLimit(maxLines)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - tar 文档（导出用）

/// 把待发布包交给系统「存储」面板。
///
/// 为什么走 `.fileExporter` 而不是自己拼路径：App 开着沙盒
/// （`ENABLE_APP_SANDBOX = YES`），只有用户**显式选的**位置才能写。
/// `.fileExporter` 拿到的就是 security-scoped 的合法位置。
struct TarArchiveDocument: FileDocument {
    /// 系统没有为 tar 单独声明 UTI 时退回 `.data`，保证面板仍能打开。
    static let tarType: UTType = UTType("public.tar-archive") ?? .data

    static var readableContentTypes: [UTType] { [tarType] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
