import Foundation

/// 保存请求按草稿、环境和请求 ID 隔离；并发保存合并，发布中新增保存继续排队。
@MainActor
public final class OpsCatalogEditSyncQueue {
    public struct Request: Equatable, Sendable {
        public let id: String
        public let draftID: String
        public let revision: Int
        public let environment: String
        public init(id: String, draftID: String, revision: Int, environment: String) {
            self.id = id; self.draftID = draftID
            self.revision = revision; self.environment = environment
        }
    }
    public enum Outcome: Equatable, Sendable {
        case confirmed(Int)
        case failed(String)
    }

    private let pending: () -> Request?
    private let isBusy: () -> Bool
    private let publish: (Request) async -> Outcome
    private let finished: (Request, Outcome) -> Void
    private let debounce: () async throws -> Void
    private var worker: Task<Void, Never>?
    private var failedRequest: Request?

    public init(pending: @escaping () -> Request?, isBusy: @escaping () -> Bool,
                publish: @escaping (Request) async -> Outcome,
                finished: @escaping (Request, Outcome) -> Void,
                debounce: @escaping () async throws -> Void = {
                    try await Task.sleep(for: .milliseconds(400))
                }) {
        self.pending = pending; self.isBusy = isBusy
        self.publish = publish; self.finished = finished; self.debounce = debounce
    }

    public func resume() {
        guard worker == nil, let request = pending(), request != failedRequest else { return }
        worker = Task { [self] in
            defer { worker = nil }
            do { try await debounce() } catch { return }
            while !isBusy(), let request = pending(), request != failedRequest {
                let result = await publish(request)
                finished(request, result)
                if case .failed = result { failedRequest = request }
                // 已尝试的请求由持久化层清除/暂停；防止回调落盘失败造成无限重复发布。
                guard pending() != request else { return }
            }
        }
    }

    public func waitUntilIdle() async { await worker?.value }

    /// 显式重试沿用原请求；是否查询冻结结果由发布层决定，队列不生成新请求。
    public func retryFailedRequest() {
        guard worker == nil else { return }
        failedRequest = nil
        resume()
    }
}
