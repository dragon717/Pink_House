//
//  OpsSettingsView.swift
//  PinkHouseOps
//
//  运营工具的**设置**（macOS `Settings` 场景，Cmd+,）。
//
//  ## 为什么这些东西在设置里
//
//  2026-10-07 起「云端同步」面板的分步卡片全部删除：运营点工具栏的
//  「云端更新」就一键发布，**无感**。但发布有三关前置（仓库目录授权 /
//  解释器 / 凭证）与一个环境选择 —— 它们是**配置**，不是「步骤」，
//  所以全部收进这里。配好一次之后日常只需要点「云端更新」。
//
//  ## 环境切换的语义
//
//  `targetEnvironment` 的 `didSet` 会清空上一个环境的线上发布号等运行态
//  （`resetEnvironmentScopedState`）—— 那份「线上 seq N」只对它读到的环境成立，
//  拿着 Development 的号去发 Production 是**没有一层会报错**的错配。
//

import AppKit
// MemberImportVisibility：`.json`（UTType）来自这个模块，不 import 会报
// “static property 'json' is not available”，那个报错看不出真正原因。
import UniformTypeIdentifiers
import SwiftUI

struct OpsSettingsView: View {
    /// 与工具栏「云端更新」、系列发布共用同一份单例（同一处真相）
    @ObservedObject private var model = OpsCloudSyncModel.shared
    /// 主窗口那份工作区（另建一份 = 两处真相，导入完主窗口还显示旧内容）
    @ObservedObject private var holder = OpsWorkspaceHolder.shared

    /// 上一次导入的结果（成功摘要 / 失败原因，二选一展示）
    @State private var importMessage: String?
    @State private var importFailed = false
    /// 上一次「数据修复」的结果（修复是破坏性的，结果必须出声）
    @State private var repairMessage: String?
    @State private var repairFailed = false
    /// 缺图文件数（打开设置时算一次 —— 每次渲染都遍历全量引用太重）
    @State private var missingCount = 0
    /// 清理悬空销售记录的**二级确认**框（弹窗快捷入口与设置按钮共用）
    @State private var showsRepairConfirm = false

    var body: some View {
        let dangling = holder.workspace?.danglingSaleEventCount ?? 0
        Form {
            Section("发布环境") {
                Picker("目标环境", selection: $model.targetEnvironment) {
                    ForEach(ShopCatalogPublishTargetEnvironment.allCases) { environment in
                        Text(environment.displayName).tag(environment)
                    }
                }
                // macOS 只有 `.radioGroup`（`.radio` 是 iOS 的写法，这里编译不过）
                .pickerStyle(.radioGroup)
                .disabled(model.isRunning)
                opsMarkdown(model.targetEnvironment.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // 切环境会清空线上发布号等运行态 —— 必须说出来，
                // 否则「刚读到的 seq」消失会被当成 bug。
                Text("切换环境会清空已读取的线上发布号与发布结论（它们只对原环境成立）。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("受控发布器（三关自检）") {
                let problems = model.diagnosis
                if problems.isEmpty {
                    Label("三关都通过，可以一键发布。", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(problems, id: \.self) { problem in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            opsMarkdown(problem)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                LabeledContent("仓库目录", value: model.settings.repoRootPath ?? "（未授权）")
                Button("选择仓库目录…") { model.chooseRepoRoot() }
                LabeledContent("解释器", value: model.interpreterText)
            }

            Section("CloudKit 凭证（按环境分开，私钥不进 App）") {
                ForEach(model.credentialStates) { state in
                    HStack(spacing: 6) {
                        Image(systemName: state.isConfigured
                              ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(state.isConfigured ? Color.green : Color.orange)
                        Text("\(state.environment.displayName)："
                             + (state.isConfigured ? "已配置" : "未配置"))
                    }
                }
                Button("导入 \(model.targetEnvironment.displayName) 凭证 JSON…") {
                    model.importCredentialFile()
                }
                if let summary = model.credentialSummary {
                    if let parseError = summary.parseError {
                        opsMarkdown("⚠️ 凭证文件读不出来：\(parseError)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text(summary.displayText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if summary.declaredEnvironmentMatches == false {
                            opsMarkdown("⚠️ 这份凭证声明的是 "
                                        + "\(summary.declaredEnvironment ?? "（未知）")，"
                                        + "与当前环境 \(model.targetEnvironment.rawValue) 不符，"
                                        + "混用只会 401。")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                opsMarkdown(model.credentialGuidance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("从 iOS 恢复（导入整包）") {
                // 「误操作覆盖了 Mac 上的内容」就用这两个入口恢复。
                // 图片**按原文件名**进 staging（引用名是交接方给的名字，
                // 改成哈希名会让目录里的 local: 引用全部悬空）。
                HStack(spacing: 10) {
                    Button("整包目录（含图片）…") { chooseAndImport(kind: .bundle) }
                    Button("仅 JSON（不含图片）…") { chooseAndImport(kind: .jsonOnly) }
                }
                Text("压缩包先在访达里双击解开，再选解开出来的那个目录"
                     + "（里面有 shop-catalog.json 和 images/）；只拿到 JSON 时选第二个。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // 破坏性动作必须写明：这正是「恢复」的语义，但同时会顶掉当前草稿。
                Text("导入会用这份内容**替换**当前草稿 —— 这就是「恢复被覆盖的内容」。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                if let importMessage {
                    opsMarkdown(importMessage)
                        .font(.caption)
                        .foregroundStyle(importFailed ? .red : .secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("数据修复（发布前的悬空引用）") {
                // 「发布前校验未通过（N 条）」里若含「销售记录 X 引用了不存在的商品 Y」，
                // 用这里清。这类记录挂不到任何商品上，客户端也显示不出来。
                // ⚠️ 门禁是跨端口径（iOS / Python 共用），不放宽它，只清数据。
                // ⚠️ 清理是**不可撤销**的删除 → 设置按钮与主窗口弹窗的快捷入口
                //    都必须过同一个二级确认框，不允许一键直达。
                HStack(spacing: 10) {
                    Button(dangling > 0
                           ? "清理悬空销售记录（\(dangling) 条）"
                           : "清理悬空销售记录") {
                        showsRepairConfirm = true
                    }
                    .disabled(dangling == 0 || holder.workspace == nil)
                    Text(dangling > 0
                         ? "当前有 \(dangling) 条销售记录指向不存在的商品，一律会被门禁拦下。"
                         : "当前没有悬空销售记录。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // 缺图不是「数据错误」，是**图不在这台机器上** —— 修不了，只能补。
                // 日志只显示前几条阻断，完整名单必须能导出，否则对着 284 这个数字无从下手。
                HStack(spacing: 10) {
                    Button("导出缺图清单…") { exportMissingImages() }
                        .disabled(missingCount == 0 || holder.workspace == nil)
                    Text(missingCount > 0
                         ? "当前有 \(missingCount) 个图片文件在本机找不到（每条引用都算一个阻断项）。"
                         : "本机不缺图片文件。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // 拼接结果 = 变量式的 String，必须过 opsMarkdown（`Text(拼接)` 不解析 Markdown）
                opsMarkdown("清理会**删除**这些销售记录（不可撤销），但它们的商品在目录里已不存在，"
                     + "本来也无从归属。整包重新导入会把它们带回来，需要再清一次。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                if let repairMessage {
                    opsMarkdown(repairMessage)
                        .font(.caption)
                        .foregroundStyle(repairFailed ? .red : .secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("日志（排查入口）") {
                HStack(spacing: 10) {
                    Button("打开最近一次日志") { model.revealLogFile() }
                        .disabled(model.logFileURL == nil)
                    Button("打开日志文件夹") { model.revealLogsFolder() }
                }
                Text("每次「云端更新 / 发布」的完整输出都落在 "
                     + "`bridge/logs/<runID>.log`（latest.log 是最近一次的副本）。"
                     + "失败时把这份文件交给 Agent 即可定位。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 720)
        // 缺图数只在这里算一次：全量引用遍历不便宜，渲染期跑不划算
        .task { missingCount = holder.workspace?.missingStagedImages().count ?? 0 }
        // 主窗口失败悬浮框的「数据修复」快捷入口落在这里：
        // 收到一次性指令 → 弹同一个二级确认框（指令用完即清，不残留）。
        .onReceive(OpsSettingsFocus.shared.$repairPromptRequested) { requested in
            guard requested else { return }
            OpsSettingsFocus.shared.repairPromptRequested = false
            if holder.workspace?.danglingSaleEventCount ?? 0 > 0 {
                showsRepairConfirm = true
            } else {
                repairFailed = false
                repairMessage = "当前没有悬空销售记录，无需清理。"
            }
        }
        .confirmationDialog(
            "清理悬空销售记录", isPresented: $showsRepairConfirm, titleVisibility: .visible
        ) {
            Button("清理 \(dangling) 条（不可撤销）", role: .destructive) {
                repairDangling()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 \(dangling) 条指向不存在商品的销售记录，删除后无法恢复。"
                 + "整包重新导入会把它们带回来，需要再清一次。")
        }
    }

    private func repairDangling() {
        guard let workspace = holder.workspace else {
            repairFailed = true
            repairMessage = "还没有可修复的工作区：请先打开主窗口（草稿库在主窗口里建）。"
            return
        }
        let removed = workspace.removeDanglingSaleEvents()
        if removed > 0 {
            repairFailed = false
            repairMessage = workspace.statusText ?? "已清理 \(removed) 条。"
        } else if let error = workspace.lastError {
            repairFailed = true
            repairMessage = error
        } else {
            // 0 条且无错误 = 确认期间数量变了，不算失败
            repairFailed = false
            repairMessage = workspace.statusText ?? "没有可清理的悬空销售记录。"
        }
    }

    /// 导出缺图清单：拿到完整名单才能去 iOS 端 / 图源逐张核对。
    /// 门禁日志只显示前几条阻断项，光看那个数字无从下手。
    private func exportMissingImages() {
        guard let workspace = holder.workspace else {
            repairFailed = true
            repairMessage = "还没有可用的工作区：请先打开主窗口（草稿库在主窗口里建）。"
            return
        }
        // 与主窗口失败悬浮框共用 `OpsMissingImagesExport`（保存面板 + 文案只写一处）
        if let message = OpsMissingImagesExport.save(from: workspace) {
            repairFailed = message.hasPrefix("导出缺图清单失败")
            repairMessage = message
        }
    }

    // MARK: 从 iOS 恢复

    /// 两种形状：解开后的整包目录（带 images/）与单独的 JSON。
    /// 服务层 `OpsWorkspace.importHandoffPackage(from:)` 两种都认
    /// （`OpsHandoffLayout.resolve`），所以这里只负责把选择形状说清楚。
    private enum ImportKind {
        case bundle
        case jsonOnly
    }

    private func chooseAndImport(kind: ImportKind) {
        guard let workspace = holder.workspace else {
            importFailed = true
            importMessage = "还没有可导入的工作区：请先打开主窗口（草稿库在主窗口里建）。"
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = (kind == .jsonOnly)
        panel.canChooseDirectories = (kind == .bundle)
        panel.allowsMultipleSelection = false
        switch kind {
        case .bundle:
            panel.message = "选择 iOS 整包解开后的目录（含 shop-catalog.json 与 images/）"
            panel.prompt = "导入整包"
        case .jsonOnly:
            panel.allowedContentTypes = [.json]
            panel.message = "选择那份 shop-catalog.json（同目录有图会一起拷）"
            panel.prompt = "导入 JSON"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // ⚠️ 结果**必须**出声：只写 lastError 不动界面 = 运营点完像没反应。
        if let report = workspace.importHandoffPackage(from: url) {
            importFailed = false
            importMessage = report.summary
                + (report.missingText.map { " ⚠️ " + $0 } ?? "")
        } else {
            importFailed = true
            importMessage = workspace.lastError ?? "导入失败（未说明原因）"
        }
    }
}
