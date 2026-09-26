//
//  OpsPublisherBridgeInterruptionTests.swift
//  PinkHouseOpsTests
//
//  桥接器「中断」这条路线的回归锁。
//
//  ## 这份测试存在的唯一理由
//
//  曾经的真实事故：收集器里有两个 `Bool`（`_timedOut` / `_cancelled`），
//  `markTimedOut()` 有人调用，**`markCancelled()` 一个人都没调用** ——
//  于是 `OpsBridgeError.cancelled` 成了一辈子走不到的分支，
//  运营点「取消当前运行」在台账上不会被标成「已取消」。
//
//  这类 bug 的特点是：**纯逻辑测试抓不到**（账本自己是对的，只是没人调用它），
//  编译器也不会报。所以下面分成两层：
//
//    · 账本与映射 —— 纯逻辑，快；
//    · ⭐ 接线 —— **真起一个子进程**，走 `cancel()` / `interrupt(.timedOut)` 这两条路，
//      断言最终抛出的错误确实是 `.cancelled` / `.timedOut`。
//      这一层才是真正能拦住上面那个 bug 的。
//
//  ## 沙盒约束（决定了桩脚本长什么样）
//
//  测试注入宿主 App 运行，而宿主是**沙盒应用**（`ENABLE_APP_SANDBOX = YES`）。
//  沙盒里只能执行系统二进制、读不到仓库目录 —— 所以这里**不用真 python**，
//  而是把 `pythonPath` 指到 `/bin/sh`，桩脚本自己就是一段 sh。
//  参数形状与真实调用逐字一致：`sh -u <脚本> --mode <m> --request <路径>`，
//  于是 `$1=--mode`、`$2=<m>`、`$3=--request`、`$4=<请求文件路径>`。
//

import XCTest
@testable import PinkHouseOpsCore
import SharedCatalog
import SharedCatalog

final class OpsPublisherBridgeInterruptionTests: XCTestCase {

    // MARK: - 中断账本（纯逻辑）

    func testEmptyLedgerResolvesToNothing() {
        let ledger = OpsBridgeInterruptionLedger()
        XCTAssertNil(ledger.interruption)
        XCTAssertNil(ledger.resolvedError)
    }

    func testUserCancelResolvesToCancelledError() {
        var ledger = OpsBridgeInterruptionLedger()
        ledger.record(.cancelledByUser)
        XCTAssertEqual(ledger.interruption, .cancelledByUser)
        XCTAssertEqual(ledger.resolvedError, .cancelled)
    }

    func testTimeoutResolvesToTimedOutErrorCarryingSeconds() {
        var ledger = OpsBridgeInterruptionLedger()
        ledger.record(.timedOut(seconds: 42))
        XCTAssertEqual(ledger.resolvedError, .timedOut(seconds: 42))
    }

    /// 先发生的那一个才算数。
    ///
    /// 超时定时器与运营点取消可能**几乎同时**到达。若让后到的覆盖先到的，
    /// 「究竟是超时还是人为取消」就取决于线程调度顺序 —— 而这俩对后续处置的
    /// 含义完全不同，不能靠巧合决定。
    func testFirstInterruptionWinsRegardlessOfOrder() {
        var timeoutFirst = OpsBridgeInterruptionLedger()
        timeoutFirst.record(.timedOut(seconds: 30))
        timeoutFirst.record(.cancelledByUser)
        XCTAssertEqual(timeoutFirst.resolvedError, .timedOut(seconds: 30),
                       "后到的取消改写了先发生的超时")

        var cancelFirst = OpsBridgeInterruptionLedger()
        cancelFirst.record(.cancelledByUser)
        cancelFirst.record(.timedOut(seconds: 30))
        XCTAssertEqual(cancelFirst.resolvedError, .cancelled,
                       "后到的超时改写了先发生的取消")
    }

    // MARK: - 映射（含两条回归锁）

    /// 每种中断都必须映射出**互不相同**的错误。
    /// 防的是复制粘贴时把两种中断指向同一个错误 —— 那样界面上「取消」会说成「超时」。
    func testEveryInterruptionMapsToADistinctError() {
        let errors = OpsBridgeInterruption.allCases.map { String(describing: $0.error) }
        XCTAssertEqual(errors.count, OpsBridgeInterruption.allCases.count)
        XCTAssertEqual(Set(errors).count, errors.count,
                       "有两种中断映射到了同一个错误，检查 OpsBridgeInterruption.error 的 switch")
    }

    /// 中断 ≠「什么都没发生」。两种中断的文案都必须要求去查结果、并禁止直接重发（R09）。
    ///
    /// 这条比看起来重要：`.cancelled` 的文案原先只有一句「受控发布已取消。」，
    /// 运营很容易理解成「取消掉了，重发一次就行」—— 而它可能已经切过发布头了。
    func testInterruptionMessagesForbidBlindResend() {
        for interruption in OpsBridgeInterruption.allCases {
            let text = interruption.error.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty, "\(interruption) 没有文案")
            XCTAssertTrue(text.contains("查询结果"),
                          "\(interruption) 的文案没让运营去查结果：\(text)")
            XCTAssertTrue(text.contains("不要直接重发"),
                          "\(interruption) 的文案没禁止直接重发：\(text)")
        }
    }

    // MARK: - 超时下限

    func testEffectiveTimeoutIsClampedToTheFloor() {
        let floor = OpsBridgeSettings.minimumTimeoutSeconds
        XCTAssertEqual(OpsBridgeSettings.effectiveTimeout(configured: 0), floor)
        XCTAssertEqual(OpsBridgeSettings.effectiveTimeout(configured: 1), floor)
        XCTAssertEqual(OpsBridgeSettings.effectiveTimeout(configured: -5), floor)
        // 边界：正好等于下限时不该被改动
        XCTAssertEqual(OpsBridgeSettings.effectiveTimeout(configured: floor), floor)
        // 正常值原样通过
        XCTAssertEqual(OpsBridgeSettings.effectiveTimeout(configured: 900), 900)
    }

    // MARK: - ⭐ 接线（真子进程）

    /// **取消**必须一路走到收集器，并最终抛出 `.cancelled`。
    ///
    /// 这就是那条真实事故的回归锁：账本本身写对没用，得有人调用它。
    func testCancelReachesCollectorAndThrowsCancelled() throws {
        let stub = try StubBridge()
        let run = stub.start()
        XCTAssertTrue(stub.waitForReady(), "桩进程没在期限内就绪：\(stub.readyPath.path)")

        run.bridge.cancel()

        XCTAssertEqual(run.finished.wait(timeout: .now() + 20), .success, "run 没有在期限内返回")
        XCTAssertEqual(run.errors.value as? OpsBridgeError, .cancelled)
    }

    /// **超时**走同一个入口，只是原因不同 —— 同样要抛出 `.timedOut`。
    ///
    /// 注意：这里直接驱动 `interrupt(_:)`，**不等真的定时器** ——
    /// 定时器的下限是 30 秒，为一条用例让整个套件慢 30 秒不划算。
    /// 定时器本身只有一行 glue（`interrupt(.timedOut(seconds: timeout))`），
    /// 它用的秒数由 `testEffectiveTimeoutIsClampedToTheFloor` 覆盖。
    func testTimeoutInterruptionThrowsTimedOut() throws {
        let stub = try StubBridge()
        let run = stub.start()
        XCTAssertTrue(stub.waitForReady(), "桩进程没在期限内就绪：\(stub.readyPath.path)")

        run.bridge.interrupt(.timedOut(seconds: 1))

        XCTAssertEqual(run.finished.wait(timeout: .now() + 20), .success, "run 没有在期限内返回")
        XCTAssertEqual(run.errors.value as? OpsBridgeError, .timedOut(seconds: 1))
    }

    /// 没有中断的调用**不该**凭空抛出中断错误 —— 否则「取消」会出现在没人取消的时候。
    ///
    /// 这里刻意**不用** try? 吞掉错误：真抛了就让用例红，而不是被兜住。
    func testRunWithoutInterruptionDoesNotThrowInterruption() throws {
        let stub = try StubBridge(sleepSeconds: 0)
        let result = try stub.run()
        XCTAssertEqual(result.bridgeSchemaVersion, ShopCatalogPublishProtocol.schemaVersion,
                       "hello 事件里的协议版本没被读出来")
        XCTAssertNil(result.outcome, "桩脚本没吐 result 事件，结论应为 nil")
    }

    // MARK: - 桩

    /// 一个「跑起来就不肯结束」的假桥接器，用来把中断路径逼出来。
    ///
    /// 刻意**不继承 `XCTestCase`**：它是夹具不是用例。
    /// 所以等待一律用 `DispatchSemaphore`，不用 `XCTestExpectation`
    /// （后者是 `XCTestCase` 的实例方法，在嵌套类型里根本编译不过）。
    struct StubBridge {

        let root: URL
        let settings: OpsBridgeSettings
        let requestPath: URL
        let readyPath: URL

        /// 一次后台调用。`finished` 在 `run` 返回或抛出后 signal。
        struct Run {
            let bridge: OpsPublisherBridge
            let errors: ErrorBox
            let finished: DispatchSemaphore
        }

        /// - Parameter sleepSeconds: 0 = 立即结束（用于「不该抛中断」那条用例）
        init(sleepSeconds: Int = 30) throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("pinkhouse-bridge-stub-\(UUID().uuidString)", isDirectory: true)
            let publication = root.appendingPathComponent("tools/time_hall/publication", isDirectory: true)
            try FileManager.default.createDirectory(at: publication, withIntermediateDirectories: true)

            // 桩脚本 = sh（见文件头的「沙盒约束」）。
            // 先吐一行合法 NDJSON（证明管道通），再写「就绪」文件，
            // 最后长睡 —— 等测试来打断它。
            let script = publication.appendingPathComponent("ops_publish_bridge.py")
            try """
            #!/bin/sh
            printf '%s\\n' '{"type":"hello","schemaVersion":1,"message":"stub bridge"}'
            : > "$4.ready"
            sleep \(sleepSeconds)
            """.write(to: script, atomically: true, encoding: .utf8)

            self.root = root
            self.requestPath = root.appendingPathComponent("request.json")
            try Data("{}".utf8).write(to: requestPath)
            self.readyPath = URL(fileURLWithPath: requestPath.path + ".ready")

            var settings = OpsBridgeSettings()
            settings.repoRootPath = root.path
            // ⚠️ 刻意用 /bin/sh 而不是 python：沙盒测试进程读不到仓库、
            // 也不保证本机装了哪种 python。而 run() 的参数形状与真实一致，
            // 所以测的仍是「同一个调用契约」。
            settings.pythonPath = "/bin/sh"
            self.settings = settings
        }

        func start() -> Run {
            let bridge = OpsPublisherBridge(settings: settings)
            let errors = ErrorBox()
            let finished = DispatchSemaphore(value: 0)
            let requestPath = self.requestPath
            DispatchQueue.global().async {
                do {
                    _ = try bridge.run(
                        mode: .publish,
                        requestPath: requestPath,
                        environmentName: "test") { _ in }
                } catch {
                    errors.set(error)
                }
                finished.signal()
            }
            return Run(bridge: bridge, errors: errors, finished: finished)
        }

        /// 等桩真的起来。
        ///
        /// 太早打断的话 `runningProcess` 还是 nil，打断会**落空** ——
        /// 然后进程一直睡到 30 秒下限，用例变成「超时」而假红。
        func waitForReady(timeout: TimeInterval = 15) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: readyPath.path) { return true }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return false
        }

        /// 同步跑一次。**只用于桩会自己结束的用例**；
        /// 中断类用例走 `start()` + `finished.wait(...)`，否则会把当前线程一直堵住。
        func run() throws -> OpsBridgeRunResult {
            try OpsPublisherBridge(settings: settings).run(
                mode: .publish,
                requestPath: requestPath,
                environmentName: "test") { _ in }
        }
    }
}

/// 跨线程回传的盒子。用锁而不是 `var` 捕获 —— 后者在严格并发下直接编译不过。
final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?

    func set(_ value: Error) { lock.lock(); stored = value; lock.unlock() }

    var value: Error? { lock.lock(); defer { lock.unlock() }; return stored }
}
