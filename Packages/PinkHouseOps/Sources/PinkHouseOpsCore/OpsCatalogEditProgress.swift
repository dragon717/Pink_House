import Foundation

public struct OpsCatalogEditProgress: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case queued, running, failed, complete }
    public struct Environment: Codable, Equatable, Sendable {
        public var stage: Int = 0
        public var detail = "等待同步"
        public var releaseSeq: Int?
    }
    public let requestID: String
    public let revision: Int
    public var state: State = .queued
    public var environments: [String: Environment] = ["development": .init(), "production": .init()]
    public var error: String?
    public init(requestID: String, revision: Int) { self.requestID = requestID; self.revision = revision }
    public var fraction: Double {
        if state == .complete { return 1 }
        return min(0.95, Double(environments.values.reduce(0) { $0 + $1.stage }) / 8)
    }
    public mutating func advance(environment: String, stage: Int, detail: String) {
        state = .running
        error = nil
        environments[environment, default: .init()].stage = max(environments[environment]?.stage ?? 0, min(3, max(0, stage)))
        environments[environment, default: .init()].detail = detail
    }
    public mutating func confirm(environment: String, releaseSeq: Int) {
        environments[environment, default: .init()].stage = 4
        environments[environment, default: .init()].detail = "内容已回读确认 · 第 \(releaseSeq) 版"
        environments[environment, default: .init()].releaseSeq = releaseSeq
        if ["development", "production"].allSatisfy({ environments[$0]?.releaseSeq != nil }) {
            state = .complete
            error = nil
        }
    }
    public mutating func fail(_ message: String) { state = .failed; error = message }
}
