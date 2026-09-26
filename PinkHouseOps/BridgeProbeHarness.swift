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
//  ## 只做只读
//
//  探针**只会**用 `--mode baseline`（只读线上发布头）。它从不构造 `--mode publish`，
//  也不设 `dryRun` 以外的任何东西 —— 探针绝不允许成为「误发一次」的来源。
//  写入只发生在容器内（`probe.log` / `probe.json`）。
//
//  ## 触发方式：文件（与快照 harness 同机制）
//
//      CONTAINER=~/Library/Containers/bugod2.ItemManager.Ops/Data/Library/Application\ Support/PinkHouseOps
//      printf 'bridge-probe' > "$CONTAINER/bridge-probe.request"     # 内容是输出子目录名，可省
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
        guard let url = OpsPublisherBridge.existingCredentialFile() else {
            record("S8", "⑥容器内凭证文件", false,
                   "不存在（约定位置 \(OpsPublisherBridge.credentialFileURL().path)）。"
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
