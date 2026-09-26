//
//  OpsValidationPanel.swift
//  PinkHouseOps
//
//  发布前校验 + 导出「待发布包」。
//
//  ⚠️ 这是一个**面板**（`VStack`，没有自己的 `ScrollView`），
//  它由「发布中心」页面嵌进去 —— 校验是发布这一段的第一步，
//  不该是侧栏里另一个和发布并排的分区：分开之后运营会在校验页点「通过」，
//  然后以为「通过了就是发出去了」。
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
//  · 本面板 `review` = 「发之前，图都准备好了吗」；
//  · 发布器在改写完 `local:` → `thmedia:` 之后还会做**后置校验**
//    （`ShopCatalogPublicationGate.issuesInPublishedCatalog`）——
//    「发之后，产物真的远端化了吗」。两者都要有，否则「上传步骤被跳过」
//    这种 bug 会一路走到线上。后置校验跑在发布器里，不在本面板。
//
//  ## 校验会过期（方案 R01）
//
//  校验结果与**编辑版本号**绑定。任何一次编辑都会作废它（`OpsWorkspace.markDirty`），
//  所以这里必须把「这份结果是第几版的」显示出来，过期就红字提示 + 禁用导出。
//  另外：**导出按钮被绕过也不等于能导出** —— `makePublicationArchive()` 自己会
//  对着当前快照再跑一次门禁，做不到「校验 A、导出 B」。
//
//  ## 策略从哪来
//
//  校验用的是**发布中心**选定的严格策略与目标环境（`OpsPublishCenter`），
//  不是这里自己再定一套 —— 否则会出现「校验按兼容口径通过、发布按严格口径被拒」，
//  而运营看到的是一句互相矛盾的提示。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OpsValidationPanel: View {
    @ObservedObject var workspace: OpsWorkspace
    @ObservedObject var center: OpsPublishCenter

    @State private var showsExporter = false
    @State private var exportDocument = TarArchiveDocument(data: Data())
    @State private var exportFileName = "pink-house-待发布包.tar"

    private var review: ShopCatalogPublicationReview? { workspace.review }

    /// 能不能导出：必须有一份**没过期**的通过结果（R01）
    private var canExport: Bool {
        guard let review, !review.isBlocked else { return false }
        return !workspace.isReviewStale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            actionCard
            versionCard
            if let review {
                conclusionCard(review)
                structuralCard(review)
                blockingCard(review)
                warningCard(review)
                requiredFilesCard(review)
                findingsCard(review)
            } else {
                OpsCard(title: "还没跑过校验（或校验已被编辑作废）",
                        systemImage: "questionmark.circle") {
                    Text("点上面的「跑一次发布前校验」，本机会把目录里所有图片引用"
                         + "逐条解一遍，告诉你哪几条解不出图。全过程不联网。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            layoutCard
        }
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
                        center.validateNow()
                    } label: {
                        Label("跑一次发布前校验", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        export()
                    } label: {
                        Label("导出待发布包（tar）", systemImage: "shippingbox")
                    }
                    .disabled(!canExport)

                    Button {
                        workspace.rescanStagingDirectory()
                        center.validateNow()
                    } label: {
                        Label("刷新素材后重跑", systemImage: "arrow.clockwise")
                    }
                }
                if workspace.isReviewStale {
                    Label("校验结果已过期：这份结果是第 \(workspace.reviewedRevision ?? 0) 版做的，"
                          + "当前已经是第 \(workspace.currentRevision) 版。请重新校验后再导出。",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                OpsFootnote(text: "· 校验只读本机目录，不联网、不写任何文件。\n"
                            + "· 用的策略与目标环境来自本页上方的「发布参数」"
                            + "（当前：\(center.strictPolicy.displayName) · "
                            + "\(center.targetEnvironment.displayName)）—— 不在这里再定一套。\n"
                            + "· 导出按钮要求「有一份没过期的通过结果」；"
                            + "即使按钮被绕过，导出服务内部也会对当前快照再校验一次。\n"
                            + "· 编辑过一次，旧结果立刻作废 —— 这是**故意**的。")
            }
        }
    }

    private func export() {
        // 先在当前快照上复校验一次：既拿到最新结论，也让界面上的 review 与版本对齐
        let fresh = center.validateNow()
        guard !fresh.isBlocked else {
            workspace.reportFailure(
                "校验未通过，不能导出："
                + "\(fresh.blockingIssues.count + fresh.catalogIssues.count) 条问题待处理。")
            return
        }
        do {
            exportDocument = TarArchiveDocument(data: try workspace.makePublicationArchive(
                strict: center.strictPolicy,
                strictScope: workspace.strictScopeIDs,
                targetEnvironmentName: center.targetEnvironment.displayName))
            exportFileName = exportName()
            showsExporter = true
            // 后置校验的**前置版本**：本地产物里仍有 `local:` 是正常的（发布器负责改写）。
            // 这里只导出，不声称已经发布。
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

    // MARK: 版本与基线（R01 / R07 留痕）

    private var versionCard: some View {
        OpsCard(title: "这份草稿的版本与基线", systemImage: "number") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("当前编辑版本", value: "第 \(workspace.currentRevision) 版")
                LabeledContent("已保存版本", value: workspace.hasUnsavedChanges
                               ? "第 \(workspace.savedRevision) 版（有未保存修改）"
                               : "第 \(workspace.savedRevision) 版（已同步）")
                LabeledContent("最后校验版本",
                               value: workspace.reviewedRevision.map { "第 \($0) 版" } ?? "未校验")
                LabeledContent("线上基线版本",
                               value: workspace.baseReleaseSeq.map { "releaseSeq \($0)" } ?? "未知（未回填）")
                LabeledContent("线上基线根摘要",
                               value: workspace.baseRootIndexHash.map { String($0.prefix(16)) + "…" }
                                   ?? "未知（未回填）")
                Divider()
                OpsFootnote(text: "⚠️ 本工具**不直连公共库**：它读不到「线上现在是什么版本」，"
                            + "只能通过受控发布器去问（发布中心的「读取线上基线」）。"
                            + "上面这两个字段只有**确认发布过 / 采纳过线上头**才有值 —— "
                            + "它们为空就是「不知道」，不是「线上是空的」。")
            }
        }
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
                     + "已远端化 \(review.remoteMediaKeys.count) 个媒体键。"
                     + "本结果对应第 \(workspace.reviewedRevision ?? 0) 版。")
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
                    opsMarkdown(item)
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
