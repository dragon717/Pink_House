//
//  OpsBridgeProbeHarness.swift
//  PinkHouseOps
//
//  发布桥接器的**沙盒行为探针**：在真实 App 里逐关实测「App 能不能驱动 Python CLI 连上 CloudKit」。
//
//  ## 为什么非要做成「App 内探针」，不能在 shell 里试
//
//  因为本机做不了沙盒实验。实测：`sandbox-exec` 只要 profile 里含任何 `deny` 规则，
//  就直接 `sandbox_exec: sandbox_apply: Operation not permitted`（连
//  `/System/Library/Sandbox/Profiles/application.sb` 也一样，且关掉工具沙箱无效）。
//  这与 `xcodebuild test` 永久挂起是同一个病根（见 skill §1e-1 / §1f）。
//
//  所以「子进程能不能读仓库」「能不能读容器内凭证」这类问题，
//  **只有在一个真正签名 + 真正沙盒的 App 进程里跑才有答案**。shell 里模拟出来的
//  结论无论绿红都是假的。
//
//  ## 为什么必须有「对照组」
//
//  这是本项目最贵的一课：**演练绿灯 ≠ 真路径正确**（离线演练用的是另一个适配器）。
//  如果只跑「打开授权之后能读到脚本」，那么在一个**根本没沙盒**的构建里也会全绿 ——
//  什么都没证明。所以每一关都是**成对**的：
//
//      · 未打开 security-scoped 扩展 → 读仓库（期望：**失败**）
//      · 打开之后                    → 同一件事（期望：成功）
//
//  两边结果**不同**才说明「授权是那个决定性的东西」。都一样就是探针本身失效（记 `inconclusive`）。
//
//  ## 只读探针 vs 发布演练（**两个触发文件，绝不合并**）
//
//  只读探针（`bridge-probe.request`）：**只会**用 `--mode baseline` / `--mode pull-catalog`
//  （两者都 `apply=False`）。它从不构造 `--mode publish` ——
//  探针绝不允许成为「误发一次」的来源。
//
//  发布演练（`publish-probe.request`，2026-10-07 补）：会构造 `--mode publish`，
//  但**固定 `dryRun=true`** —— 于是它真跑 `build_release.py`（这正是 09-29
//  在沙盒里炸掉的那一步），而发布器走 `--dry-run` 不写库。收尾还有一道反证：
//  演练前后各读一次线上发布头，**发布号必须不变**。
//
//  ⭐ 两条链路坚持用两个触发文件，是因为「只读」这句承诺依赖「谁也不会顺手跑它」。
//  合并的话，为看一眼 S9/S10 而写下触发文件的人就会顺带跑一遍发布链路 ——
//  那正是本项目最贵的一课（演练绿灯 ≠ 真路径正确）的另一种翻版：
//  约束写在注释里，而注释不拦人。
//
//  ## 触发方式：文件（与快照 harness 同机制）
//
//      CONTAINER=~/Library/Containers/bugod2.ItemManager.Ops/Data/Library/Application\ Support/PinkHouseOps
//      printf 'bridge-probe' > "$CONTAINER/bridge-probe.request"     # 内容是输出子目录名，可省
//      open -n build/sym/Debug/PinkHouseOps.app
//
//  发布演练另需先把整包放进容器（沙盒读不到 /tmp）：
//
//      cp release.tar "$CONTAINER/publish-probe-stage/release.tar"
//      printf 'publish-probe' > "$CONTAINER/publish-probe.request"
//      open -n build/sym/Debug/PinkHouseOps.app
//
//  产物：`<容器>/Library/Application Support/PinkHouseOps/<子目录名>/probe.log`（人读）
//  与 `probe.json`（机读，可 diff 两次运行）。
//
//  ## 隐私
//
//  凭证文件**只报结构不报内容**：文件名、字节数、JSON 顶层键名。
//  私钥、keyID、containerID 一律不进日志 —— 探针的日志是要被贴进对话里看的。
//

import AppKit
import Foundation
import SharedCatalog

@MainActor
enum OpsBridgeProbeHarness {

    /// 触发文件名（放在应用容器的 `Application Support/PinkHouseOps/` 下）
    static let requestFileName = "bridge-probe.request"

    /// 默认输出子目录名（触发文件为空时用它）
    static let defaultOutputFolderName = "bridge-probe"

    /// 探针给桥接留的超时（秒）。比正式发布的 900s 短得多：
    /// 探针是**同步阻塞**跑的，挂死时没人能点取消 —— 短超时本身就是安全阀。
    static let probeTimeoutSeconds = 120

    /// 容器内的数据根目录。与 `OpsWorkspace.rootDirectory` 同一算法，
    /// 刻意不共享代码（探针要在 workspace 之前跑，不该依赖它）。
    static func rootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PinkHouseOps", isDirectory: true)
    }

    /// 有触发文件就返回输出目录并**消费掉触发文件**（避免下次启动又跑）。
    static func pendingRequest() -> URL? {
        let root = rootDirectory()
        let marker = root.appendingPathComponent(requestFileName)
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let requested = (try? String(contentsOf: marker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try? FileManager.default.removeItem(at: marker)
        let folder = (requested?.isEmpty == false) ? requested! : defaultOutputFolderName
        return root.appendingPathComponent(folder, isDirectory: true)
    }

    // MARK: - 发布演练的触发文件（与只读探针**刻意分成两个**）

    /// 发布演练（S11）的触发文件名。
    ///
    /// ⭐ 为什么不复用 `bridge-probe.request`：本文件开头对只读探针的承诺是
    /// 「只会用 `--mode baseline`……从不构造 `--mode publish`，也不设 `dryRun`
    /// 以外的任何东西 —— 探针绝不允许成为『误发一次』的来源」。
    /// 把演练挂在同一个触发文件上，那句承诺当场作废：谁为了看一眼 S9/S10
    /// 写下 `bridge-probe.request`，都会顺带跑一遍完整发布链路。
    /// 拆成两个文件之后，「看只读」与「看发布」是两个**显式**动作。
    static let publishRequestFileName = "publish-probe.request"

    /// 演练整包目录名（操作者先把 `release.tar` 放进这里）。
    ///
    /// 必须在**容器内**：沙盒 App 读不到容器外的路径（如 `/tmp`），
    /// 而且**不会报错**，只是读不到 —— 于是表现为「整包不存在」。
    static let publishStageFolderName = "publish-probe-stage"

    /// 演练输出子目录的缺省名（触发文件为空时用它）。
    static let defaultPublishOutputFolderName = "publish-probe"

    /// 演练超时。比只读探针（120s）宽得多：这一关要真的跑
    /// `build_release.py`（规范化图片 + 打包 + 复校验），几十兆图片要几分钟。
    static let publishProbeTimeoutSeconds = 600

    static func pendingPublishRequest() -> URL? {
        let root = rootDirectory()
        let marker = root.appendingPathComponent(publishRequestFileName)
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let requested = (try? String(contentsOf: marker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try? FileManager.default.removeItem(at: marker)
        let folder = (requested?.isEmpty == false) ? requested! : defaultPublishOutputFolderName
        return root.appendingPathComponent(folder, isDirectory: true)
    }

    // MARK: - 记录

    /// 一关的结论。`ok == nil` 表示**没法判定**（例如对照组与实验组一样），
    /// 它**不算通过** —— 探针里没有「默认通过」这种事。
    private struct Step {
        var id: String
        var title: String
        var ok: Bool?
        var detail: String
    }

    private static var steps: [Step] = []
    private static var logLines: [String] = []

    private static func record(_ id: String, _ title: String, _ ok: Bool?, _ detail: String) {
        steps.append(Step(id: id, title: title, ok: ok, detail: detail))
        let mark = ok == nil ? "??" : (ok! ? "✓ " : "✗ ")
        logLines.append("\(mark) [\(id)] \(title) — \(detail)")
    }

    private static func log(_ line: String) {
        logLines.append("   " + line)
    }

    // MARK: - 入口

    static func run(into directory: URL) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            // 目录都建不出来，日志无处可写 —— 只能打 stdout（唯一一处例外）
            print("PROBE 建目录失败：\(error.localizedDescription)")
            return
        }
        steps.removeAll()
        logLines.removeAll()
        defer { write(directory) }

        log("PROBE 开始，输出目录 \(directory.path)")
        log("PROBE 只做只读探测（桥接只用 --mode baseline），不会写线上任何内容。")

        // 先把「不依赖授权」的两关做完，再做「需要授权」的两关。
        // 顺序不能反：`startAccessingSecurityScopedResource` 一旦调用，
        // 未授权状态就再也回不去了（同一进程内）。
        probeSettings()
        probeUnauthorizedControl()
        guard let settings = decodedSettings() else {
            record("S9", "端到端 baseline", false, "没有可解码的桥接设置，跳过（关口⑤未过）")
            return
        }
        probeAuthorized(settings)
        probeCredentialFile()
        await probeBaseline(settings)
        await probePullCatalog(settings)
    }

    private static func write(_ directory: URL) {
        // 结论汇总：任何一关 `ok != true` 都必须在**第一屏**就看得见。
        let failed = steps.filter { $0.ok != true }
        let verdict = failed.isEmpty
            ? "全部通过（\(steps.count) 关）"
            : "\(failed.count)/\(steps.count) 关未通过：" + failed.map(\.id).joined(separator: "、")
        logLines.append("")
        logLines.append("PROBE 结论：\(verdict)")

        let text = logLines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("probe.log"), atomically: true, encoding: .utf8)

        // 机读版：两次运行可以直接 diff（凭证/私钥绝不进来）
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "verdict": verdict,
            "steps": steps.map { ["id": $0.id, "title": $0.title, "ok": $0.ok as Any, "detail": $0.detail] },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("probe.json"))
        }
        // 沙箱 App 拿不到 stdout，日志必须跟着产物走；结论同时打一行到 stdout 便于
        // 从 `log stream` 里捞（有就当彩头，没有也不影响验收）。
        print("PROBE 结论：\(verdict)")
    }

    // MARK: - S1 设置（关口⑤ 的前半）

    private static func decodedSettings() -> OpsBridgeSettings? {
        guard let data = UserDefaults.standard.data(forKey: OpsBridgeSettings.defaultsKey),
              let settings = try? JSONDecoder().decode(OpsBridgeSettings.self, from: data) else {
            return nil
        }
        return settings
    }

    private static func probeSettings() {
        guard let settings = decodedSettings() else {
            record("S1", "读到桥接设置（关口⑤）", false,
                   "UserDefaults 里没有 `\(OpsBridgeSettings.defaultsKey)`。"
                   + "说明用户从未在发布中心里授权过仓库目录 —— 先授权再跑探针。")
            return
        }
        let bookmark = settings.repoRootBookmark.map { "\($0.count) 字节" } ?? "无"
        record("S1", "读到桥接设置（关口⑤）", true,
               "repoRootPath=\(settings.repoRootPath ?? "nil") · bookmark=\(bookmark)"
               + " · pythonPath=\(settings.pythonPath ?? "自动") · timeout=\(settings.timeoutSeconds)s")
    }

    // MARK: - S2 未授权对照（**关键**：没有对照组，绿灯不算数）

    private static func probeUnauthorizedControl() {
        guard let settings = decodedSettings(), let script = settings.scriptPath else {
            record("S2", "未授权对照：仓库真的读不到", nil, "没有设置，做不了对照（先过 S1）")
            return
        }
        // ⭐ 判据是**真读**，不是 `fileExists`：2026-09-27 实测这两者在沙盒下不同源
        // （`fileExists`=true 而 `Data(contentsOf:)`=Operation not permitted）。
        // 拿 `fileExists` 当判据的话，这一关会「因为能读到而失败」，把结论完全带偏。
        let read = readability(script.path)
        let child = runChild("/bin/ls", [script.deletingLastPathComponent().path])
        record("S2", "未授权对照：仓库真的读不到", !read.ok,
               "\(read.description)（期望：真读失败）· 子进程 ls 退出码=\(child.exitCode)（期望非 0）"
               + (child.output.isEmpty ? "" : " · 子进程说：\(firstLine(child.output))"))
        if read.ok || child.exitCode == 0 {
            log("⚠️ 未授权就能读到仓库：要么这个 App 没在沙盒里跑（那后面的结论都不成立），"
                + "要么该路径在别处已获授权（此时本对照失效，别把它当证据）。")
        }
    }

    /// 真实可读性：`fileExists` 与「真读」在沙盒下**不同源**，必须分别报。
    private static func readability(_ path: String) -> (ok: Bool, description: String) {
        let visible = FileManager.default.fileExists(atPath: path)
        let bytes = (try? Data(contentsOf: URL(fileURLWithPath: path)))?.count
        let readText = bytes.map { "\($0) 字节" } ?? "失败"
        var description = "fileExists=\(visible) · 真读=\(readText)"
        if visible && bytes == nil {
            // 这正是「存在性检查骗人」的形状，值得单独点一句。
            description += " ⚠️（stat 通过、open 被拒 —— 存在性检查在这里不可信）"
        }
        return (bytes != nil, description)
    }

    // MARK: - S3/S4 授权后（关口⑤ 的后半 + ⑥b 核心）

    private static func probeAuthorized(_ settings: OpsBridgeSettings) {
        guard let script = settings.scriptPath, let publication = settings.publicationDirectory else {
            record("S3", "打开 security-scoped 授权", false, "设置里没有可用的仓库路径")
            return
        }
        // 复用 `OpsBridgeSettings.beginAuthorizedRepoRootScope()`（**不再自己写一份**）：
        // 探针早先抄了一遍 bookmark 解析，那就是「副本必然与本体漂移」的典型 ——
        // 桥接器换了参数而探针没换，探针就会开始给出与真实路径无关的结论。
        if settings.repoRootBookmark == nil {
            record("S3", "打开 security-scoped 授权", false,
                   "设置里只有路径、没有 bookmark —— 非沙盒下能用，**沙盒下必然读不到**。"
                   + "（用户在发布中心选择一次目录才会写入 bookmark。）")
        }
        let access = settings.beginAuthorizedRepoRootScope()
        if settings.repoRootBookmark != nil {
            record("S3", "打开 security-scoped 授权", access.accessed,
                   "startAccessingSecurityScopedResource() → \(access.accessed)"
                   + "（false = bookmark 失效或本进程已在别处持有）")
        }
        // 子进程探测必须在**授权仍有效**时做。
        defer { access.stop() }

        let read = readability(script.path)
        var head = "-"
        if let data = try? Data(contentsOf: script) {
            head = String(decoding: data.prefix(48), as: UTF8.self)
                .replacingOccurrences(of: "\n", with: "⏎")
        }
        record("S4", "授权后读仓库脚本（与 S2 对照）", read.ok,
               "\(read.description)（期望：真读成功）· 头 48 字节=\(head)")

        // ⚠️ 这里**不能** `return`。读不到目录列表**正是未授权场景应有的结果**，
        // 而 S6（子进程读仓库）与 S7（哪个解释器带 cryptography）是它的对照组 ——
        // 提前返回会让「未授权」这一侧的证词缺一半，只剩一句「S5 失败」，
        // 于是又回到「只看到一个红叉、不知道红在哪」的老毛病。
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: publication.path) {
            let venv = publication.appendingPathComponent(".venv/bin/python3")
            record("S5", "列发布目录内容", entries.contains("ops_publish_bridge.py"),
                   "\(entries.count) 项 · 含桥接脚本=\(entries.contains("ops_publish_bridge.py"))"
                   + " · 含 .venv/bin/python3=\(FileManager.default.fileExists(atPath: venv.path))")
        } else {
            record("S5", "列发布目录内容", false,
                   "读不到目录列表（\(publication.path)）—— 授权没生效时这是**预期**结果")
        }

        // ⭐ ⑥b：**子进程**能不能读仓库？这才是「App 驱动 CLI」成立与否的分水岭。
        // 父进程能读不等于子进程能读（安全作用域扩展是进程级的，随 fork/exec 继承，
        // 但这句「随 fork/exec 继承」必须实测而不是引用文档）。
        let child = runChild("/bin/ls", [publication.path])
        record("S6", "⑥b 子进程读仓库（授权有效时）", child.exitCode == 0 && !child.output.isEmpty,
               "子进程 ls 退出码=\(child.exitCode) · 输出 \(child.output.split(separator: "\n").count) 行"
               + (child.output.isEmpty ? "" : " · 首行：\(firstLine(child.output))"))

        probeInterpreters(settings: settings, publication: publication)
    }

    /// 关口②：**哪个解释器带 `cryptography`**。
    /// 逐个候选跑一次子进程才知道 —— 因为子进程读不到仓库外的 site-packages，
    /// 而系统 `python3` 本机确实没装（系统版 3.9.6），且它在沙盒里会在
    /// `xcrun` 那一层就被拒（`cannot be used within an App Sandbox`）。
    ///
    /// 候选顺序**直接取自 `OpsBridgeSettings.pythonCandidates`** ——
    /// 探针要报告的是「真实解析顺序下哪个会被选中」，自己另排一遍顺序就等于
    /// 在验证一个不存在的流程。
    private static func probeInterpreters(settings: OpsBridgeSettings, publication: URL) {
        var results: [String] = []
        var anyOK = false
        for candidate in OpsBridgeSettings.pythonCandidates(explicit: settings.pythonPath,
                                                            publicationDirectory: publication) {
            guard FileManager.default.isExecutableFile(atPath: candidate) else {
                // ⚠️ 措辞不能说「不存在」：无授权时**看不见**与**真没有**在这里分不开，
                // 而把「看不见」写成「不存在」正是本项目反复踩的那类假证词。
                results.append("\(candidate)=不可执行（不存在，或本进程没有该路径的访问权）")
                continue
            }
            let probe = runChild(candidate, [
                "-c", "import sys,cryptography;print(sys.version.split()[0],cryptography.__version__)",
            ])
            if probe.exitCode == 0 {
                anyOK = true
                results.append("\(candidate)=\(firstLine(probe.output))")
            } else {
                results.append("\(candidate)=退出码 \(probe.exitCode)（\(firstLine(probe.output))）")
            }
        }
        record("S7", "②哪个解释器带 cryptography", anyOK, results.joined(separator: " · "))
    }

    // MARK: - S8 容器内凭证（关口⑥）

    private static func probeCredentialFile() {
        guard let url = OpsPublisherBridge.existingCredentialFile(environmentName: "development") else {
            record("S8", "⑥容器内凭证文件", false,
                   "不存在（约定位置 \(OpsPublisherBridge.credentialFileURL(environmentName: "development").path)）。"
                   + "CLI 会回退去读登录钥匙串，而子进程继承 App 沙盒 → 读不到 → 会报「凭证不可用」。")
            return
        }
        // 只报结构，**不报内容**（私钥/keyID/containerID 一律不进日志）。
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        var keys = "-"
        var environmentValue = "-"
        if let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            keys = object.keys.sorted().joined(separator: ",")
            environmentValue = (object["environment"] as? String) ?? "（未声明）"
        }
        record("S8", "⑥容器内凭证文件", keys != "-",
               "存在 · \(size) 字节 · 顶层键=\(keys) · environment=\(environmentValue)")

        // 子进程能不能读到它？—— 容器内路径对子进程应是可读的，但要证明。
        let child = runChild("/bin/cat", [url.path])
        record("S8b", "⑥b 子进程读容器内凭证", child.exitCode == 0,
               "子进程 cat 退出码=\(child.exitCode) · 读到 \(child.output.utf8.count) 字节")
    }

    // MARK: - S9 端到端（只读的一条链路）

    private static func probeBaseline(_ settings: OpsBridgeSettings) async {
        let directory = rootDirectory().appendingPathComponent("bridge-probe-run", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 请求全部字段都填上：桥接器对必填字段是**硬校验**（缺一个就 refused），
        // 而这里的失败信息会直接暴露「App 与 CLI 的字段口径是否一致」。
        let request = ShopCatalogPublishRequest(
            requestID: "probe-baseline",
            jobID: "probe",
            draftID: "probe",
            draftRevision: 0,
            baseReleaseSeq: nil,
            baseRootIndexHash: nil,
            baselineAcknowledged: false,
            targetEnvironment: .development,
            releaseSeq: 1,
            inputDirectory: directory.appendingPathComponent("input").path,
            archivePath: directory.appendingPathComponent("none.tar").path,
            outputDirectory: directory.appendingPathComponent("output").path,
            receiptPath: directory.appendingPathComponent("receipt.json").path,
            filesystemRoot: nil,
            dryRun: true,
            payloadHash: "probe")
        let requestURL = directory.appendingPathComponent("request.json")
        do {
            try request.encoded().write(to: requestURL, options: .atomic)
        } catch {
            record("S9", "端到端 baseline（只读）", false, "写请求文件失败：\(error.localizedDescription)")
            return
        }

        // 探针自己的超时（短）——设置是值类型，拷一份改就行，不动用户设置。
        var probeSettings = settings
        probeSettings.timeoutSeconds = probeTimeoutSeconds

        let bridge = OpsPublisherBridge(settings: probeSettings)
        let box = OpsBridgeProbeEventBox()
        do {
            let result = try await Task.detached(priority: .userInitiated) { () throws -> OpsBridgeRunResult in
                try bridge.run(mode: .baseline, requestPath: requestURL, environmentName: "development") { event in
                    // 回调在管道读取线程；探针只需要计数，用一个锁保护。
                    box.append(event)
                }
            }.value
            let head = result.onlineHead
            // ⭐ 这一关**不**断言「读到了线上发布头」：线上可能真的还没有发布头。
            // 它断言的是「链路走通了」——即桥接器下了一个结论，而不是抛错/什么都不说。
            var detail = "exitCode=\(result.exitCode) · 事件 \(result.events.count) 条"
            if let value = head { detail += " · 线上 releaseSeq=\(value.releaseSeq)" }
            else { detail += " · 没有 baseline 事件（线上可能确实还没有发布头）" }
            if let outcome = result.outcome { detail += " · outcome=\(outcome.rawValue)" }
            if let message = result.outcomeMessage { detail += " · \(message)" }
            if !result.nonJSONLines.isEmpty {
                detail += " · 非 JSON 行 \(result.nonJSONLines.count) 条，首条：\(firstLine(result.nonJSONLines[0]))"
            }
            // 协议版本不一致会让桥接器直接抛错（而那是另一件要修的事），单独点出来。
            record("S9", "端到端 baseline（只读）", result.isProtocolCompatible && head != nil
                   || (result.isProtocolCompatible && result.outcome != nil), detail)
            log("S9 事件轨迹：\(result.stageTrail.map(\.rawValue).joined(separator: " → "))")
        } catch {
            let message = error.localizedDescription
            record("S9", "端到端 baseline（只读）", false, "抛出：\(message)")
            log("S9 收到的最后几行事件："
                + (box.snapshot().suffix(3).compactMap(\.displayLine).joined(separator: " / ")))
        }
    }

    // MARK: - S10 端到端（只读的第二条链路：把线上目录**拉回本地**）

    /// 「云端同步」面板的「从云端下载」走的就是这一条。
    ///
    /// 为什么 S9 已绿还要再来一关：S9 只证明「能读到发布头」，而下载这条链路上
    /// 还多两件只有真跑才知道的事 ——
    ///   ① CLI 得把整份目录落盘到**沙盒容器内**（写不进去就是下载不可用）；
    ///   ② App 侧要靠 `catalog` 事件里的路径与条数把它解析成 `OpsPulledCatalog`
    ///      （字段名一旦对不上，界面就永远显示「没拉到东西」，而 CLI 那边全是绿的）。
    /// 所以这里**复用生产解析路径** `OpsPulledCatalog.from`，不另写一份判定。
    ///
    /// 仍是**只读**：`--mode pull-catalog` 全程 `apply=False`，不写线上任何东西。
    private static func probePullCatalog(_ settings: OpsBridgeSettings) async {
        let directory = rootDirectory().appendingPathComponent("bridge-probe-pull", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let request = ShopCatalogPublishRequest(
            requestID: "probe-pull",
            jobID: "probe",
            draftID: "probe",
            draftRevision: 0,
            baseReleaseSeq: nil,
            baseRootIndexHash: nil,
            baselineAcknowledged: false,
            targetEnvironment: .development,
            releaseSeq: 1,
            inputDirectory: directory.appendingPathComponent("input").path,
            archivePath: directory.appendingPathComponent("none.tar").path,
            outputDirectory: directory.path,
            receiptPath: directory.appendingPathComponent("receipt.json").path,
            filesystemRoot: nil,
            dryRun: true,
            payloadHash: "probe-pull")
        let requestURL = directory.appendingPathComponent("request.json")
        do {
            try request.encoded().write(to: requestURL, options: .atomic)
        } catch {
            record("S10", "端到端 pull-catalog（只读）", false, "写请求文件失败：\(error.localizedDescription)")
            return
        }

        var probeSettings = settings
        probeSettings.timeoutSeconds = probeTimeoutSeconds
        let bridge = OpsPublisherBridge(settings: probeSettings)
        do {
            let result = try await Task.detached(priority: .userInitiated) { () throws -> OpsBridgeRunResult in
                try bridge.run(mode: .pullCatalog, requestPath: requestURL, environmentName: "development") { _ in }
            }.value

            guard let pulled = OpsPulledCatalog.from(result: result, environment: "development") else {
                // 「拉不到」有两种：线上确实没有目录（正常），或事件字段对不上（缺陷）。
                // 不区分就等于把缺陷说成正常，所以两种形态都写进 detail。
                record("S10", "端到端 pull-catalog（只读）", false,
                       "exitCode=\(result.exitCode) · 但没有 catalog 事件（未拿到落盘路径）。"
                       + "线上若确实没有商店目录，这是正常结果；"
                       + "否则要查 `pulledCatalogPath` 的字段口径。"
                       + " · 结论=\(result.outcome?.rawValue ?? "无")"
                       + (result.outcomeMessage.map { " · \($0)" } ?? ""))
                return
            }
            // 判据是**真读**，不是 fileExists（沙盒里 stat 与 open 不同源）。
            let readable = OpsBridgeSettings.isReadableFile(URL(fileURLWithPath: pulled.path))
            record("S10", "端到端 pull-catalog（只读）", readable,
                   "exitCode=\(result.exitCode) · \(pulled.summaryText)"
                   + " · 落盘文件可读=\(readable) · 路径=\(pulled.path)")
            log("S10 各类条数：" + pulled.sortedItemCounts
                .map { "\($0.field)=\($0.count)" }.joined(separator: " "))
        } catch {
            record("S10", "端到端 pull-catalog（只读）", false, "抛出：\(error.localizedDescription)")
        }
    }

    // MARK: - 入口（发布演练）

    /// 发布演练的入口。与 `run(into:)` 是**两个独立入口**，互不隐含。
    ///
    /// 前面几关（设置 / 未授权对照 / 凭证）刻意复用同一批函数：
    /// 它们是「这个进程真的在沙盒里」的前提证明 —— 少了 S2 的对照组，
    /// 后面「沙盒内能跑通发布」这句话可以被一个**没沙盒**的构建伪造出来。
    static func runPublish(into directory: URL) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("PROBE 建目录失败：\(error.localizedDescription)")
            return
        }
        steps.removeAll()
        logLines.removeAll()
        defer { write(directory) }

        log("PROBE（发布演练）开始，输出目录 \(directory.path)")
        log("PROBE 用 --mode publish + dryRun=true：**会**真跑 build_release.py，"
            + "但发布器走 --dry-run，不写线上任何内容。")

        // 「不依赖授权」的几关必须排在前面（见 `run(into:)` 的顺序说明）。
        probeSettings()
        probeUnauthorizedControl()
        probeCredentialFile()
        guard let settings = decodedSettings() else {
            record("S11d", "沙盒内跑发布链路（dry run）", false,
                   "没有可解码的桥接设置，跳过（先过 S1）")
            return
        }
        await probePublishDryRun(settings)
    }

    // MARK: - S11 沙盒内真跑一次发布链路（dry run，不写线上）

    /// 这一关只回答一个问题：**「在真 App 沙盒里，`--mode publish` 那条链路跑得通吗？」**
    ///
    /// ## 为什么非要有它（2026-10-07 补）
    ///
    /// App 侧最后一次真实发布是 **09-29 02:23**，死在 `build_release.py:396` 的
    /// `mimetypes.guess_type()` → `PermissionError: '/etc/apache2/mime.types'`。
    /// 之后 MIME 判定改走 `protocol.media_mime_type()`（纯查表），
    /// **但修复之后再没在沙盒里重跑过**。而那个 bug 只在沙盒里出现
    /// （shell 直跑复现不出）—— 也就是说「CLI 能发」完全证明不了「App 能发」。
    /// 2026-10-07 我在 CLI 里连发了 seq 3 / seq 4 都成功，那两张证书对这条链路
    /// **一张都不算**。
    ///
    /// ## 为什么是 dry run 就够
    ///
    /// `run_publish` **即使 dry run 也会先跑 `build_release.py`**
    /// （`ops_publish_bridge.py` 里就是 `--dry-run` / `--apply` 一个分支的差别），
    /// 而 `build_release.py` 恰恰就是当年炸掉的那一步。之后
    /// `publish_cloudkit.py --dry-run` 不写库 —— 探针仍然不是「误发一次」的来源。
    ///
    /// ## 反证（这一步不能省）
    ///
    /// 演练前后各读一次线上发布头，**发布号必须不变**。没有这一步，
    /// 「没写线上」只是我们的声明，不是观察到的事实。
    private static func probePublishDryRun(_ settings: OpsBridgeSettings) async {
        let root = rootDirectory()
        let stage = root.appendingPathComponent(publishStageFolderName, isDirectory: true)
        let archive = stage.appendingPathComponent("release.tar")

        var probeSettings = settings
        probeSettings.timeoutSeconds = publishProbeTimeoutSeconds
        let bridge = OpsPublisherBridge(settings: probeSettings)

        // ---- 11a 整包就位（**真读**，不用 fileExists —— 沙盒里它骗人）
        guard let archiveData = try? Data(contentsOf: archive) else {
            record("S11a", "演练整包就位（容器内）", false,
                   "读不到 \(archive.path) —— 沙盒 App 读不到容器外的路径（如 /tmp，"
                   + "且不会报错）。请先把 release.tar 放进这个目录再跑。")
            return
        }
        let payloadHash = ShopCatalogSyncProtocol.sha256Hex(archiveData)
        record("S11a", "演练整包就位（容器内）", true,
               "\(archiveData.count) 字节 · sha256=\(payloadHash.prefix(12))…")

        // ---- 11b 演练前：读线上发布头（同时就是 R07 要回填的那份基线）
        let beforeDirectory = root.appendingPathComponent("publish-probe-before", isDirectory: true)
        guard let before = await readHeadOnce(
            bridge: bridge, directory: beforeDirectory, tag: "publish-probe-before"),
            let head = before.onlineHead else {
            record("S11b", "演练前读线上发布头", false,
                   "没读到发布头 → 基线回填不出来 → 演练会因 R07 被拒。"
                   + "那说明「读」这一半坏了，**不能**据此说「发布链路坏了」。")
            return
        }
        record("S11b", "演练前读线上发布头", true,
               "releaseSeq=\(head.releaseSeq) · rootIndexHash=\(head.rootIndexHash?.prefix(12) ?? "未读到")…")

        // ---- 11c 构造发布请求
        let runDirectory = root.appendingPathComponent("publish-probe-run", isDirectory: true)
        let inputDirectory = runDirectory.appendingPathComponent("input", isDirectory: true)
        let outputDirectory = runDirectory.appendingPathComponent("output", isDirectory: true)
        let receiptPath = runDirectory.appendingPathComponent("receipt.json")
        try? FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        // 产物目录必须是「空」或「看起来就是发布产物」，否则桥接器会拒绝
        // （它不替运营删东西）。每次演练从干净的一份开始，结论才可比。
        try? FileManager.default.removeItem(at: outputDirectory)

        let request = ShopCatalogPublishRequest(
            requestID: "publish-probe-\(UUID().uuidString)",
            jobID: "probe",
            draftID: "probe",
            draftRevision: 0,
            // 基线用**真线上**的号与摘要回填，并且**不**勾「已知线上已变」——
            // 让 R07 闸门自己走出「一致」这条路，而不是被那条例外旁路掉。
            // （旁路掉的话，这一关就再也证明不了「App 与线上口径对得上」。）
            baseReleaseSeq: head.releaseSeq,
            baseRootIndexHash: head.rootIndexHash,
            baselineAcknowledged: false,
            targetEnvironment: .development,
            releaseSeq: head.releaseSeq + 1,
            inputDirectory: inputDirectory.path,
            archivePath: archive.path,
            outputDirectory: outputDirectory.path,
            receiptPath: receiptPath.path,
            filesystemRoot: nil,
            dryRun: true,
            payloadHash: payloadHash)
        let requestURL = runDirectory.appendingPathComponent("request.json")
        do {
            try request.encoded().write(to: requestURL, options: .atomic)
        } catch {
            record("S11c", "构造发布请求", false, "写请求文件失败：\(error.localizedDescription)")
            return
        }
        record("S11c", "构造发布请求", true,
               "seq \(head.releaseSeq) → \(head.releaseSeq + 1) · dryRun=true"
               + " · 基线由桥接器自己读回，未旁路 R07")

        // ---- 11d 真跑（只有这一步会启动 build_release.py 的子进程）
        let box = OpsBridgeProbeEventBox()
        do {
            let result = try await Task.detached(priority: .userInitiated) { () throws -> OpsBridgeRunResult in
                try bridge.run(
                    mode: .publish,
                    requestPath: requestURL,
                    environmentName: "development"
                ) { event in
                    box.append(event)
                }
            }.value

            let trail = result.stageTrail.map(\.rawValue)
            // 判据落在**构建那一段真的走完了**上：只断言 `exitCode == 0` 不够 ——
            // 被 R07 拒掉也是非 0，而那种非 0 什么也没证明；反过来，
            // `build` 出现在轨迹里 = `build_release.py` 在沙盒里跑到了发 `succeeded`。
            //
            // ⚠️ 不要在这里要求 `verifyArtifact`（我第一版就写错了）：`stageTrail`
            // 只收 `state == .started` 的事件（见 `OpsPublisherBridge._stages`），
            // 而 Python 的 `freeze` 与 `verifyArtifact` **只发 `succeeded`、从不发 `started`**
            // —— 于是这两个阶段**本来就不该**出现在轨迹里，拿它当判据是假失败。
            let builtInsideSandbox = trail.contains(ShopCatalogPublishStage.build.rawValue)
            var detail = "exitCode=\(result.exitCode) · 阶段轨迹=\(trail.joined(separator: " → "))"
            detail += " · 产物 rootIndexHash=\(result.artifactRootIndexHash?.prefix(12) ?? "无")"
            if let value = result.artifactReleaseSeq { detail += " · 产物 seq=\(value)" }
            detail += " · 结论=\(result.outcome?.rawValue ?? "dry-run 成功不发 outcome 事件")"
            if !result.nonJSONLines.isEmpty {
                detail += " · 非 JSON 行 \(result.nonJSONLines.count) 条"
            }
            record("S11d", "沙盒内跑 build_release.py（dry run）",
                   result.exitCode == 0 && builtInsideSandbox && result.artifactRootIndexHash != nil,
                   detail)
            // ⭐ 已知缺口（**不是**本关的判据，但必须写下来，否则读日志的人会误判）：
            // 轨迹里有 `switchHead` / `confirmHead`，而这是一次**什么都没写**的演练。
            // 成因：`run_child` 是按子进程打印的步骤标记翻译阶段的，与 dry_run 无关，
            // 而 `publish_cloudkit.py --dry-run` 照样把七步的名字都打出来。
            // 为什么现在不判它失败：`OpsBridgeRunResult.reachedHeadSwitch` 全仓
            // **只有声明、没有任何消费方**（死代码），而 App 侧「记一次已发布」
            // 受 `dryRun == false && receipt.readBackConfirmed == true` 门禁 ——
            // 所以演练的状态判定是对的（回执也如实写着上传 0/4 张、0/1 个包）。
            // 真正的风险是**文档与命名**：它自称「R09 判定的关键输入」，
            // 一旦有人照这句话把它接进「结果待确认」的判定，演练（以及演练后被打断
            // 的那条路径）就会被误判成「可能已经切过头」。接之前必须先让它认得 dryRun。
            if result.reachedHeadSwitch {
                log("注：dry run 的轨迹也播报到了 \(trail.last ?? "-")（reachedHeadSwitch=true）。"
                    + "这是文案层面的已知缺口，不影响判定（该属性无消费方）。")
            }
            if result.exitCode != 0 {
                log("S11d 最后几行："
                    + box.snapshot().suffix(4).compactMap(\.displayLine).joined(separator: " / "))
            }
            if let receipt = result.receipt {
                log("S11d 回执：releaseSeq=\(String(describing: receipt.releaseSeq))"
                    + " · readBackConfirmed=\(String(describing: receipt.readBackConfirmed))"
                    + " · 上传媒体 \(String(describing: receipt.uploadedMedia))/"
                    + "\(String(describing: receipt.totalMedia))"
                    + " · 上传包 \(String(describing: receipt.uploadedPacks))/"
                    + "\(String(describing: receipt.totalPacks))")
            }
        } catch {
            record("S11d", "沙盒内跑 build_release.py（dry run）", false,
                   "抛出：\(error.localizedDescription)")
            log("S11d 收到的最后几行事件："
                + box.snapshot().suffix(3).compactMap(\.displayLine).joined(separator: " / "))
            return
        }

        // ---- 11e 反证：线上发布号必须**没变**
        let afterDirectory = root.appendingPathComponent("publish-probe-after", isDirectory: true)
        guard let after = await readHeadOnce(
            bridge: bridge, directory: afterDirectory, tag: "publish-probe-after"),
            let afterHead = after.onlineHead else {
            record("S11e", "反证：演练后线上发布号未变", false,
                   "演练后读不到发布头 —— 「没写线上」这句话**没有观察到**，因此不算已证。")
            return
        }
        let unchanged = afterHead.releaseSeq == head.releaseSeq
        record("S11e", "反证：演练后线上发布号未变", unchanged,
               "演练前 seq=\(head.releaseSeq)，演练后 seq=\(afterHead.releaseSeq)"
               + (unchanged
                  ? " —— dry run 确实没有动线上。"
                  : " —— ⚠️ 发布号变了：dry run 没有生效，**立即停止一切发布动作**。"))
    }

    /// 一次只读的「读线上发布头」。S11 前后各用一次：
    /// 前面用它取基线（回填请求），后面用它做反证。
    ///
    /// 刻意**不**复用 `probeBaseline`：那一关有自己的结论与计数器口径，
    /// 把它的记录逻辑抽出来会在两处之间造出「同一条判定两份实现」的漂移面。
    private static func readHeadOnce(
        bridge: OpsPublisherBridge, directory: URL, tag: String
    ) async -> OpsBridgeRunResult? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let request = ShopCatalogPublishRequest(
            requestID: tag,
            jobID: "probe",
            draftID: "probe",
            draftRevision: 0,
            baseReleaseSeq: nil,
            baseRootIndexHash: nil,
            baselineAcknowledged: false,
            targetEnvironment: .development,
            releaseSeq: 1,
            inputDirectory: directory.appendingPathComponent("input").path,
            archivePath: directory.appendingPathComponent("none.tar").path,
            outputDirectory: directory.appendingPathComponent("output").path,
            receiptPath: directory.appendingPathComponent("receipt.json").path,
            filesystemRoot: nil,
            dryRun: true,
            payloadHash: "probe")
        let requestURL = directory.appendingPathComponent("request.json")
        do {
            try request.encoded().write(to: requestURL, options: .atomic)
        } catch {
            log("读基线：写请求文件失败 \(error.localizedDescription)")
            return nil
        }
        do {
            return try await Task.detached(priority: .userInitiated) { () throws -> OpsBridgeRunResult in
                try bridge.run(
                    mode: .baseline, requestPath: requestURL, environmentName: "development") { _ in }
            }.value
        } catch {
            log("读基线抛出：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 子进程

    /// 同步跑一个子进程，返回 (退出码, 合并后的输出)。**会阻塞**，所以只用于短命令。
    ///
    /// 刻意不复用 `OpsPublisherBridge`：那个是「发布」用的，参数是审过的固定形状；
    /// 探针要能跑任意诊断命令，两件事不该共用一条路径（否则探针就成了「参数注入」的面）。
    private static func runChild(_ executable: String, _ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "启动失败：\(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 事件盒子

/// 桥接器的事件回调在**管道读取线程**上跑（见 `OpsPublisherBridge`），
/// 而探针在 `Task.detached` 里等它结束 —— 所以这个盒子必须能跨线程。
/// 只有 `NSLock` 一把锁：探针不做实时 UI，不需要更复杂的东西。
///
/// ⚠️ `nonisolated` 是**必须的**，不是装饰：本 target 开了
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`（见 pbxproj），
/// 于是文件里**所有类型默认主线程隔离** —— 不写 `nonisolated` 的话
/// `append` 就成了 MainActor 方法，在管道读取线程上调用会直接告警
/// （`call to main actor-isolated instance method in a synchronous nonisolated context`），
/// 而且这个告警很轻，轻到容易被当成噪音放过。
private nonisolated final class OpsBridgeProbeEventBox: @unchecked Sendable {

    private let lock = NSLock()
    private var events: [ShopCatalogPublishEvent] = []

    func append(_ event: ShopCatalogPublishEvent) {
        lock.lock(); events.append(event); lock.unlock()
    }

    func snapshot() -> [ShopCatalogPublishEvent] {
        lock.lock(); defer { lock.unlock() }; return events
    }
}
