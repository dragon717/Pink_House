//
//  OpsPublishCenterView.swift
//  PinkHouseOps
//
//  发布中心：一次新上的**发布**这一段（方案 §4 / §5 / §6）。
//
//  ## 这一页最重要的三件事，都是「不许把两件事说成一件」
//
//  1. **四个状态永不合并**：
//        导出成功 ≠ 发布成功 ≠ 远端已生效 ≠ 每台设备已同步
//     所以页面上没有任何一个「发布成功」的绿点。任务的状态只说**执行**状态
//     （已冻结 / 构建中 / 上传中 / 结果待确认 / 发布已确认），
//     「已确认」旁边永远跟着一句「不代表每台离线设备都已刷新」。
//
//  2. **结果待确认时，只给「查询结果」，不给「重发」**（R09）。
//     这不是靠文案劝导，而是**按钮根本不出现**：动作按钮由
//     `ShopCatalogPublishExecutionState.allowsResubmit` / `.requiresResultQuery`
//     决定。把「不明」当「可重试」就是重复发布 —— 会把已经前进的线上版本
//     用旧内容写回去。
//
//  3. **严格策略必须把作用域显示出来**（R08），**演练必须说自己只是演练**。
//     一个看不见作用域的「严格」等于没开；一个不说明演练的环境名
//     （`本机演练`）会被读成「已经上线了」。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OpsPublishCenterView: View {
    @ObservedObject var workspace: OpsWorkspace
    @ObservedObject var center: OpsPublishCenter

    @State private var showsRepoPicker = false
    @State private var selectedJobID: String?
    /// 替换草稿内容的确认（**一次内容替换不该由一次点击悄悄完成**）
    @State private var showsAdoptPulledConfirm = false

    private var selectedJob: OpsPublishJob? {
        guard let selectedJobID else { return nil }
        return center.jobs.first { $0.requestID == selectedJobID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                feedbackBanner
                bridgeCard
                parametersCard
                baselineCard
                pulledCatalogCard
                blockersCard
                freezeCard
                progressCard
                changeSetCard
                // 校验与产物导出是**发布这一段的第一步**，所以它嵌在发布中心里，
                // 而不是侧栏里另一个同级的页面 —— 分开会让「校验通过」被读成「已发布」。
                OpsValidationPanel(workspace: workspace, center: center)
                jobsCard
                if let job = selectedJob {
                    jobDetailCard(job)
                }
                conclusionsCard
            }
            .padding(18)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(
            isPresented: $showsRepoPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                center.authorizeRepository(at: url)
            case .failure(let error):
                center.clearError()
                // 面板层面的失败没有别的通道，直接说
                print("选择仓库目录失败：\(error.localizedDescription)")
            }
        }
        .onAppear {
            center.suggestedReleaseSeqText()
            if selectedJobID == nil { selectedJobID = center.jobs.first?.requestID }
        }
        .onChange(of: center.jobs.count) { _, _ in
            if selectedJob == nil { selectedJobID = center.jobs.first?.requestID }
        }
        .confirmationDialog(
            "用线上拉回的内容替换当前草稿？",
            isPresented: $showsAdoptPulledConfirm,
            titleVisibility: .visible
        ) {
            Button("替换（丢了本地未发布的改动）", role: .destructive) {
                _ = center.adoptPulledCatalog()
            }
            Button("取消", role: .cancel) {}
        } message: {
            // ⚠️ 这里原来是 `Text("…" + "…")` —— 拼接结果是一个 **String 变量**，
            // 走逐字初始化器、**不解析 Markdown**，`**替换**` 的星号会照原样显示。
            // 只有**单个**字面量才自动走 `LocalizedStringKey`。
            opsMarkdown("这是**替换**不是合并：当前草稿里未发布的改动会丢掉。"
                        + "拉回的内容是已下发口径（不含归档条目、图片是 thmedia: 引用）。")
        }
    }

    // MARK: 反馈（发布中心自己的通道）

    /// 发布中心的 `lastError` / `lastMessage` 与 `OpsWorkspace` 是两套状态，
    /// 所以这一页自己有横幅 —— **但它只有一条**，不各卡各报（同 `OpsStatusBanner` 的理由）。
    @ViewBuilder
    private var feedbackBanner: some View {
        if let error = center.lastError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                opsMarkdown(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("知道了") { center.clearError() }.buttonStyle(.link)
            }
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        } else if let message = center.lastMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                opsMarkdown(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: 桥接器自检

    private var bridgeCard: some View {
        OpsCard(title: "发布桥接（受控发布器）", systemImage: "cable.connector") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("仓库目录", value: center.settings.repoRootPath ?? "未设置")
                LabeledContent("发布脚本",
                               value: center.settings.scriptPath?.path ?? "找不到（看下面的问题）")
                LabeledContent("Python 解释器",
                               value: center.settings.resolvedPythonPath() ?? "找不到（看下面的问题）")
                LabeledContent("超时（秒）", value: "\(center.settings.timeoutSeconds)")
                HStack(spacing: 10) {
                    Button {
                        showsRepoPicker = true
                    } label: {
                        Label("选择仓库目录…", systemImage: "folder.badge.gearshape")
                    }
                    .controlSize(.small)
                    OpsFootnote(text: "选择的目录会存成 security-scoped bookmark —— "
                                + "App 开着沙盒，只有你显式选过的目录才读得到。")
                }
                if center.bridgeProblems.isEmpty {
                    Label("桥接器就绪。", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("桥接器不可用（\(center.bridgeProblems.count) 条）",
                              systemImage: "xmark.circle.fill")
                            .font(.callout).foregroundStyle(.red)
                        ForEach(center.bridgeProblems, id: \.self) { problem in
                            opsMarkdown("· " + problem)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                OpsFootnote(text: "这一页**不直连公共库**：它只调用仓库里的受控发布器，"
                            + "签名私钥留在 Keychain，不进 App、不进日志。")
            }
        }
    }

    // MARK: 发布参数

    private var parametersCard: some View {
        OpsCard(title: "发布参数", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("目标环境", selection: $center.targetEnvironment) {
                    ForEach(ShopCatalogPublishTargetEnvironment.allCases) { environment in
                        Text(environment.displayName).tag(environment)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(center.isBusy)
                .onChange(of: center.targetEnvironment) { _, _ in
                    // 换环境之后旧的「已核对基线」无效：基线与回执都是**按环境**的
                    center.baselineAcknowledged = false
                }
                OpsFootnote(text: center.targetEnvironment.guidance)

                Divider()
                Picker("引用校验策略", selection: $center.strictPolicy) {
                    ForEach(ShopCatalogStrictPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                OpsFootnote(text: center.strictPolicy.guidance)
                HStack(spacing: 8) {
                    OpsTag(text: "严格作用域 \(center.strictScopeCount) 个实体",
                           tint: center.strictScopeCount > 0 ? .accentColor : .secondary)
                    OpsFootnote(text: "作用域 = 与基线快照**差**出来的那部分（推导的，不是谁上报的）。"
                                + "只收紧本次新增 / 修改过的内容，存量旧数据按兼容口径走。")
                }

                Divider()
                Toggle(isOn: $center.useDryRun) {
                    Text("演练（构建 + 校验 + 计划，但**不写线上**）")
                }
                OpsFootnote(text: center.useDryRun
                            ? "演练开着：本次不会写任何远端内容，回执里 applied=false，"
                              + "**这不代表已上线**。"
                            : "演练关着：本次会真的写目标环境。建议先在 Development 演练一次。")
            }
        }
    }

    // MARK: 线上基线（R07）

    private var baselineCard: some View {
        OpsCard(title: "线上基线与发布号（R07）", systemImage: "arrow.left.arrow.right") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await center.refreshBaseline() }
                    } label: {
                        Label("读取线上基线", systemImage: "arrow.down.circle")
                    }
                    .disabled(center.isBusy || center.isReadingBaseline || !center.bridgeProblems.isEmpty)
                    if center.isReadingBaseline { ProgressView().controlSize(.small) }
                    if let readAt = center.baselineReadAt {
                        OpsFootnote(text: "读取于 " + readAt.formatted(date: .abbreviated, time: .standard))
                    }
                }
                verdictRow

                if let head = center.onlineHead {
                    LabeledContent("线上发布号", value: "\(head.releaseSeq)")
                    LabeledContent("线上根清单摘要", value: head.hashText)
                    if let publishedAt = head.publishedAt {
                        LabeledContent("线上发布时间", value: publishedAt)
                    }
                    Button("把线上头采用为这份草稿的基线") {
                        center.adoptOnlineHeadAsBaseline()
                    }
                    .controlSize(.small)
                    .help("显式动作：只有你确认线上内容就是这份草稿的起点时才点")
                } else {
                    OpsFootnote(text: "还没有读到线上发布头。没读到 = 无法核对，"
                                + "**不等于**线上是空的。")
                }

                Divider()
                HStack(spacing: 10) {
                    TextField("本次发布号", text: $center.releaseSeqText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Button("用建议值 \(center.suggestedReleaseSeq)") {
                        center.releaseSeqText = "\(center.suggestedReleaseSeq)"
                    }
                    .controlSize(.small)
                }
                OpsFootnote(text: "建议值 = 线上 +1、本机记录过的最大号 +1、草稿基线 +1 三者取最大。"
                            + "发布号必须**严格递增**：要回到旧内容请走回滚流程（那也是另一个号）。")
            }
        }
    }

    // MARK: 从线上拉回基线（方案 §5）

    /// 这一步补的是「基线**内容**」。
    ///
    /// 在此之前 App 只有「导入 JSON」：本地那份东西与线上是什么关系，没有任何依据；
    /// 桥接器也无从核对 `baseRootIndexHash`（它从没见过线上那份内容）。
    /// 拉回是**只读**的，取回后还要运营显式确认才会替换草稿。
    @ViewBuilder
    private var pulledCatalogCard: some View {
        OpsCard(title: "从线上拉回基线（方案 §5）", systemImage: "arrow.down.doc") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await center.pullCatalogFromOnline() }
                    } label: {
                        Label("从线上拉回基线", systemImage: "arrow.down.circle")
                    }
                    .disabled(center.isBusy || center.isPullingCatalog
                              || !center.bridgeProblems.isEmpty)
                    .help("只读：把线上那份完整商店目录取回本地。它不写线上，也不动你的草稿。")
                    if center.isPullingCatalog { ProgressView().controlSize(.small) }
                }
                OpsFootnote(text: "只读操作：既不写线上，也不改当前草稿。"
                            + "取回之后**还要你确认一次**才会替换内容（替换 = 覆盖，不是合并）。")

                if let pulled = center.pulledCatalog {
                    Divider()
                    LabeledContent("来源环境", value: pulled.environment)
                    LabeledContent("线上发布号", value: "\(pulled.releaseSeq)")
                    LabeledContent("根清单摘要", value: pulled.hashText)
                    ForEach(pulled.sortedItemCounts) { row in
                        LabeledContent(row.label, value: "\(row.count)")
                    }
                    if let payloadHash = pulled.payloadHash {
                        LabeledContent("载荷摘要", value: String(payloadHash.prefix(12)) + "…")
                    }

                    if !center.pulledCatalogCaveats.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("替换草稿之前请先读这几条",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundStyle(.orange)
                            ForEach(center.pulledCatalogCaveats, id: \.self) { note in
                                opsMarkdown("· " + note)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 8))
                    }

                    HStack(spacing: 10) {
                        Button("用这份内容替换当前草稿") { showsAdoptPulledConfirm = true }
                            .disabled(!center.pulledCatalogAdoptionBlockers.isEmpty || center.isBusy)
                        Button("放弃") { center.discardPulledCatalog() }
                            .controlSize(.small)
                    }
                    ForEach(center.pulledCatalogAdoptionBlockers, id: \.self) { blocker in
                        opsMarkdown("· " + blocker)
                            .font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let note = center.pulledCatalogNote {
                    OpsFootnote(text: note)
                }
            }
        }
    }

    @ViewBuilder
    private var verdictRow: some View {
        let verdict = center.baselineVerdict
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: verdict.isVerified
                      ? "checkmark.seal.fill" : "questionmark.diamond.fill")
                    .foregroundStyle(verdict.isVerified ? Color.green
                                     : (verdict.isBlocking ? Color.red : Color.orange))
                Text("基线核对：\(verdict.displayName)").font(.callout.weight(.medium))
            }
            OpsFootnote(text: verdict.guidance)
            if !verdict.isVerified {
                Toggle(isOn: $center.baselineAcknowledged) {
                    Text("我已确认：没有其他人在这份草稿之后发过（读不到线上时的唯一出口，会记进请求里可审计）")
                        .font(.callout)
                }
            }
        }
    }

    // MARK: 提交前阻断项

    private var blockersCard: some View {
        let blockers = center.submissionBlockers
        return OpsCard(title: blockers.isEmpty ? "可以提交" : "提交前还有 \(blockers.count) 项要处理",
                       systemImage: blockers.isEmpty ? "checkmark.circle" : "hand.raised") {
            if blockers.isEmpty {
                OpsFootnote(text: "所有前置条件都满足了。点「冻结这次发布」生成不可变请求。")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(blockers, id: \.self) { blocker in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5)).foregroundStyle(.orange).padding(.top, 6)
                            opsMarkdown(blocker).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: 冻结与提交

    private var freezeCard: some View {
        OpsCard(title: "冻结与提交", systemImage: "snowflake") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        if let job = center.freeze() { selectedJobID = job.requestID }
                    } label: {
                        Label("冻结这次发布", systemImage: "snowflake")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!center.canSubmit || center.isBusy)

                    if let active = center.activeJob, active.state.allowsResubmit, !center.isBusy {
                        Button {
                            Task { await center.submit(active) }
                        } label: {
                            Label("提交这条已冻结的任务", systemImage: "paperplane.fill")
                        }
                    }
                    if center.isBusy {
                        Button("取消当前运行") { center.cancelCurrentRun() }
                        ProgressView().controlSize(.small)
                    }
                }
                OpsFootnote(text: "冻结 = 把「这次要发的是什么」固化成不可变请求（产物摘要 + 编辑版本号 + 基线）。"
                            + "同一份快照重复提交会复用同一个请求号（幂等）；编辑过之后就是新内容、新请求号。")
                if let active = center.activeJob {
                    HStack(spacing: 8) {
                        OpsTag(text: "当前任务 \(active.state.displayName)",
                               tint: active.state.isLive ? .green : .accentColor)
                        OpsTag(text: active.targetEnvironment.displayName,
                               tint: active.targetEnvironment.isRealRemote ? .accentColor : .orange)
                        OpsFootnote(text: "第 \(active.draftRevision) 版 · releaseSeq \(active.releaseSeq)")
                    }
                }
            }
        }
    }

    // MARK: 进度

    @ViewBuilder
    private var progressCard: some View {
        if let job = center.activeJob ?? center.jobs.first(where: { $0.isRunning }) {
            OpsCard(title: "当前任务进度", systemImage: "gauge.with.dots.needle.33percent") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        OpsTag(text: job.state.displayName,
                               tint: job.state.isLive ? .green : .accentColor)
                        if job.hasUnitProgress {
                            Text("\(job.completedUnits)/\(job.totalUnits)")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                    }
                    sevenSteps(job)
                    OpsFootnote(text: job.state.guidance)
                    if !center.liveLines.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("事件留痕（尾部）").font(.caption.weight(.semibold))
                            ForEach(Array(center.liveLines.suffix(8).enumerated()), id: \.offset) { _, line in
                                // 事件留痕里也有 `**…**`（如「⚠️ 基线不一致（运营已显式确认继续）」），
                                // 所以同样要过 `opsMarkdown`，否则星号会逐字进日志。
                                opsMarkdown(line)
                                    .font(.caption2).monospaced()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    /// 七步顺序（方案 §5.1）。**第 6 步是唯一的生效点**，单独标出来。
    private func sevenSteps(_ job: OpsPublishJob) -> some View {
        let stages: [ShopCatalogPublishStage] = [
            .verifyArtifact, .readHead, .uploadMedia, .uploadPacks,
            .readBack, .switchHead, .confirmHead,
        ]
        let reached = job.stage?.stepOrdinal ?? 0
        return HStack(spacing: 4) {
            ForEach(stages, id: \.rawValue) { stage in
                let ordinal = stage.stepOrdinal ?? 0
                let isDone = ordinal < reached || (ordinal == reached && !job.isRunning)
                let isCurrent = ordinal == reached && job.isRunning
                VStack(spacing: 3) {
                    Text("\(ordinal)")
                        .font(.caption2.weight(.bold))
                        .frame(width: 18, height: 18)
                        .background(
                            (isDone ? Color.green : (isCurrent ? Color.accentColor : Color.secondary))
                                .opacity(isDone || isCurrent ? 0.22 : 0.12),
                            in: Circle())
                        .foregroundStyle(isDone ? Color.green
                                         : (isCurrent ? Color.accentColor : Color.secondary))
                    Text(stage.displayName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 62)
                }
                if ordinal < 7 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.20))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: 差异清单（R08 作用域可见）

    private var changeSetCard: some View {
        let changeSet = center.changeSet
        return OpsCard(title: "这次发布改了什么（与基线快照的差分）", systemImage: "plus.forwardslash.minus") {
            VStack(alignment: .leading, spacing: 8) {
                if !changeSet.hasBaseline {
                    // 同上：`"…" + "…"` 是变量，`**整份目录**` 的星号会逐字显示。
                    Label {
                        opsMarkdown("还没有基线快照：差分只能按「本地新增」来算，"
                                    + "严格策略的作用域因此是**整份目录**。")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if changeSet.isEmpty {
                    OpsFootnote(text: "与基线没有差异（或还没有基线）。")
                } else {
                    ForEach(changeSet.summaryLines, id: \.self) { line in
                        opsMarkdown("· " + line).font(.callout)
                    }
                }
                OpsFootnote(text: "判定方式：逐实体按 id 与基线快照比对（同 id 两侧相等 = 未改）。"
                            + "墓碑（下架）单独列 —— 它表达「下架」而不是「漏传」。")
            }
        }
    }

    // MARK: 任务台账

    private var jobsCard: some View {
        OpsCard(title: "发布任务台账（\(center.jobs.count)）", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                if center.jobs.isEmpty {
                    OpsFootnote(text: "还没有发布过。冻结一次发布之后，这里会逐条记账 —— "
                                + "包括**中断后没下结论**的那些（否则重启后唯一的动作就是重发）。")
                } else {
                    ForEach(center.jobs) { job in
                        jobRow(job)
                        Divider()
                    }
                }
            }
        }
    }

    private func jobRow(_ job: OpsPublishJob) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: job.state))
                    .frame(width: 8, height: 8)
                Text(job.state.displayName).font(.callout.weight(.medium))
                OpsTag(text: "releaseSeq \(job.releaseSeq)", tint: .secondary)
                OpsTag(text: job.targetEnvironment.displayName,
                       tint: job.targetEnvironment.isRealRemote ? .accentColor : .orange)
                if job.receipt?.applied == false {
                    OpsTag(text: "演练（未写线上）", tint: .orange)
                }
                if job.needsAttention { OpsTag(text: "待处理", tint: .orange) }
                Spacer(minLength: 4)
                Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            OpsFootnote(text: "第 \(job.draftRevision) 版 · 尝试 \(job.attemptCount) 次 · "
                        + "产物摘要 \(String(job.payloadHash.prefix(12)))…")
            if let stage = job.stage {
                OpsFootnote(text: "阶段：\(stage.displayName)"
                            + (stage.changesLiveVersion ? "（**这一步之后线上才变**）" : ""))
            }
            if let message = job.lastErrorMessage {
                opsMarkdown(message)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            jobActions(job)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { selectedJobID = job.requestID }
        .background(selectedJobID == job.requestID
                    ? Color.accentColor.opacity(0.07) : Color.clear)
    }

    /// ⭐ 动作按钮**由状态机决定**，不是由界面作者记得住决定。
    ///
    /// `allowsResubmit` 在 `pendingConfirmation` 上是 false，所以「重发」根本
    /// 不会被渲染出来 —— R09 的「只给查询」是编译期就成立的，不靠文案劝导。
    @ViewBuilder
    private func jobActions(_ job: OpsPublishJob) -> some View {
        HStack(spacing: 8) {
            if job.state.requiresResultQuery {
                Label("结果待确认：先查询线上发布头，**不要重发**",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("查询结果") {
                Task { await center.queryResult(job) }
            }
            .controlSize(.small)
            .disabled(center.isBusy)

            if job.state.allowsResubmit, !center.isBusy {
                Button(job.state == .frozen ? "提交" : "重试") {
                    Task { await center.retry(job) }
                }
                .controlSize(.small)
            }
            if job.state == .confirmed {
                Button("用这条回执更新基线") {
                    // 回执就是「线上已经是这一版」的证据：采纳它作为下次的基线
                    center.adoptOnlineHeadAsBaseline()
                }
                .controlSize(.small)
                .disabled(center.onlineHead == nil)
                .help("把当前读到的线上头采用为这份草稿的基线（需要先「读取线上基线」）")
            }
            if !job.isRunning, job.state.isTerminal {
                Button("从台账移除") { center.removeJob(job) }
                    .controlSize(.small)
            }
        }
        .buttonStyle(.bordered)
    }

    private func color(for state: ShopCatalogPublishExecutionState) -> Color {
        switch state {
        case .confirmed: return .green
        case .pendingConfirmation, .conflict, .retryableFailure: return .orange
        case .refused, .replaced: return .red
        case .frozen: return .secondary
        case .building, .uploading, .verifying, .switchingHead: return .accentColor
        }
    }

    // MARK: 单条任务详情（回执）

    private func jobDetailCard(_ job: OpsPublishJob) -> some View {
        OpsCard(title: "任务详情", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("请求号（幂等键）", value: job.requestID)
                LabeledContent("任务号", value: job.jobID)
                LabeledContent("草稿版本", value: "第 \(job.draftRevision) 版")
                LabeledContent("目标环境", value: job.targetEnvironment.displayName)
                LabeledContent("适配器", value: job.adapter.displayName)
                LabeledContent("发布号", value: "\(job.releaseSeq)")
                LabeledContent("冻结时基线",
                               value: job.baseReleaseSeq.map { "releaseSeq \($0)" } ?? "无（未回填）")
                LabeledContent("产物摘要", value: job.payloadHash)
                if let directory = job.outputDirectory {
                    LabeledContent("产物目录", value: directory)
                }
                Divider()
                if let receipt = job.receipt {
                    Text("回执").font(.callout.weight(.semibold))
                    LabeledContent("回执结论") { opsMarkdown(receipt.summaryText) }
                    LabeledContent("是否已应用写入", value: receipt.applied == true ? "是" : "否（演练或未写入）")
                    LabeledContent("回读确认", value: receipt.readBackConfirmed == true ? "是" : "否")
                    if let hash = receipt.rootIndexHash {
                        LabeledContent("回执里的根摘要", value: hash)
                    }
                    if let previous = receipt.previousChangeTag, let current = receipt.newChangeTag {
                        LabeledContent("changeTag", value: "\(previous) → \(current)")
                    }
                    if let verifiedAt = receipt.verifiedAt {
                        LabeledContent("回读时刻",
                                       value: verifiedAt.formatted(date: .abbreviated, time: .standard))
                    }
                } else {
                    OpsFootnote(text: "还没有回执。**「没有回执」不等于「没有生效」**："
                                + "切发布头之后响应丢失时就是这种状态，必须用「查询结果」去核对线上。")
                }
                if !job.logLines.isEmpty {
                    Divider()
                    Text("事件留痕（\(job.logLines.count) 条）").font(.callout.weight(.semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(job.logLines.enumerated()), id: \.offset) { _, line in
                            // 同「事件留痕」：日志行里的 `**…**` 也要真的加粗
                            opsMarkdown(line)
                                .font(.caption2).monospaced()
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: 口径说明

    private var conclusionsCard: some View {
        OpsCard(title: "四个状态，永不合并", systemImage: "exclamationmark.bubble") {
            VStack(alignment: .leading, spacing: 6) {
                Text("导出成功　≠　发布成功　≠　远端已生效　≠　每台设备已同步")
                    .font(.callout.weight(.medium))
                    .monospaced()
                OpsFootnote(text: "· 「已冻结」只说明产物和请求落好了，线上一个字都没变；\n"
                            + "· 「发布已确认」= 回读确认线上发布头指向本次产物；"
                            + "它**仍然不代表**每台离线设备都已刷新；\n"
                            + "· 第 6 步（切换发布头）是**唯一**让新版本生效的动作 —— "
                            + "在那之前失败，线上还是旧版，可以安全重试；\n"
                            + "· 在那之后结果不明，只能查询，不能重发。")
            }
        }
    }
}
