//
//  Logger.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import Foundation
import os

struct AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.pinkhouse.itemmanager"
    private static let logger = Logger(subsystem: subsystem, category: "General")

    static func category(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
    
    static func log(_ message: String, type: OSLogType = .default) {
        logger.log(level: type, "\(message)")
    }
    
    static func error(_ message: String) {
        log(message, type: .error)
    }
    
    static func info(_ message: String) {
        log(message, type: .info)
    }
}

enum MenuPerfSignpost {
    #if DEBUG
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.pinkhouse.itemmanager"
    private static let logger = Logger(subsystem: subsystem, category: "MenuPerf")
    private static let signposter = OSSignposter(logger: logger)

    @discardableResult
    static func menuOpen(_ name: String) -> Bool {
        signposter.emitEvent("menu_open", "name=\(name, privacy: .public)")
        return true
    }

    @discardableResult
    static func menuContent(_ name: String) -> Bool {
        signposter.emitEvent("menu_content_eval", "name=\(name, privacy: .public)")
        return true
    }

    @discardableResult
    static func contextMenuOpen(_ name: String) -> Bool {
        signposter.emitEvent("context_menu_open", "name=\(name, privacy: .public)")
        return true
    }

    @discardableResult
    static func facetCacheRefresh(inputCount: Int, outputCount: Int) -> Bool {
        signposter.emitEvent(
            "facet_cache_refresh",
            "input=\(inputCount, privacy: .public) output=\(outputCount, privacy: .public)"
        )
        return true
    }
    #else
    @discardableResult
    static func menuOpen(_ name: String) -> Bool { true }

    @discardableResult
    static func menuContent(_ name: String) -> Bool { true }

    @discardableResult
    static func contextMenuOpen(_ name: String) -> Bool { true }

    @discardableResult
    static func facetCacheRefresh(inputCount: Int, outputCount: Int) -> Bool { true }
    #endif
}

enum DraftReliabilitySignpost {
    #if DEBUG
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.pinkhouse.itemmanager"
    private static let logger = Logger(subsystem: subsystem, category: "DraftReliability")
    private static let signposter = OSSignposter(logger: logger)

    @discardableResult
    static func editorInit(isEditing: Bool, continueFromDraft: Bool, sessionID: UUID) -> Bool {
        signposter.emitEvent(
            "editor_init",
            "isEditing=\(isEditing, privacy: .public) continueFromDraft=\(continueFromDraft, privacy: .public) session=\(sessionID.uuidString, privacy: .public)"
        )
        return true
    }

    @discardableResult
    static func editorModelInit() -> Bool {
        signposter.emitEvent("editor_model_init")
        return true
    }

    @discardableResult
    static func draftSave(scope: String, draftID: UUID, imageCount: Int, tagCount: Int, byteSize: Int, reason: String = "") -> Bool {
        signposter.emitEvent(
            "draft_save",
            "scope=\(scope, privacy: .public) draftID=\(draftID.uuidString, privacy: .public) images=\(imageCount, privacy: .public) tags=\(tagCount, privacy: .public) bytes=\(byteSize, privacy: .public) reason=\(reason, privacy: .public)"
        )
        return true
    }

    @discardableResult
    static func draftLoad(scope: String, source: String, draftID: UUID?, imageCount: Int) -> Bool {
        signposter.emitEvent(
            "draft_load",
            "scope=\(scope, privacy: .public) source=\(source, privacy: .public) draftID=\(draftID?.uuidString ?? "nil", privacy: .public) images=\(imageCount, privacy: .public)"
        )
        return true
    }

    @discardableResult
    static func draftClear(scope: String, reason: String) -> Bool {
        signposter.emitEvent(
            "draft_clear",
            "scope=\(scope, privacy: .public) reason=\(reason, privacy: .public)"
        )
        return true
    }

    @discardableResult
    static func draftSaveFailed(scope: String, error: Error) -> Bool {
        logger.error("draft_save_failed scope=\(scope, privacy: .public) error=\(String(describing: error), privacy: .public)")
        signposter.emitEvent(
            "draft_save_failed",
            "scope=\(scope, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
        return true
    }

    @discardableResult
    static func scenePhase(_ phase: String, reason: String) -> Bool {
        signposter.emitEvent(
            "scene_phase",
            "phase=\(phase, privacy: .public) reason=\(reason, privacy: .public)"
        )
        return true
    }
    #else
    @discardableResult
    static func editorInit(isEditing: Bool, continueFromDraft: Bool, sessionID: UUID) -> Bool { true }

    @discardableResult
    static func editorModelInit() -> Bool { true }

    @discardableResult
    static func draftSave(scope: String, draftID: UUID, imageCount: Int, tagCount: Int, byteSize: Int, reason: String = "") -> Bool { true }

    @discardableResult
    static func draftLoad(scope: String, source: String, draftID: UUID?, imageCount: Int) -> Bool { true }

    @discardableResult
    static func draftClear(scope: String, reason: String) -> Bool { true }

    @discardableResult
    static func draftSaveFailed(scope: String, error: Error) -> Bool { true }

    @discardableResult
    static func scenePhase(_ phase: String, reason: String) -> Bool { true }
    #endif
}

enum PerformanceSignpost {
    enum Operation {
        case routeTransition
        case wardrobeRebuild
        case depositUpdate
        case monthStats

        #if DEBUG
        fileprivate var name: StaticString {
            switch self {
            case .routeTransition:
                return "route_transition"
            case .wardrobeRebuild:
                return "wardrobe_rebuild"
            case .depositUpdate:
                return "deposit_update"
            case .monthStats:
                return "month_stats"
            }
        }
        #endif
    }

    struct Interval {
        #if DEBUG
        fileprivate let operation: Operation
        fileprivate let state: OSSignpostIntervalState
        #endif
    }

    #if DEBUG
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.pinkhouse.itemmanager"
    private static let logger = Logger(subsystem: subsystem, category: "Performance")
    private static let signposter = OSSignposter(logger: logger)

    @discardableResult
    static func begin(_ operation: Operation, label: String = "", detail: String = "") -> Interval {
        let state = signposter.beginInterval(
            operation.name,
            "label=\(label, privacy: .public) detail=\(detail, privacy: .public)"
        )
        return Interval(operation: operation, state: state)
    }

    static func end(_ interval: Interval, detail: String = "") {
        signposter.endInterval(
            interval.operation.name,
            interval.state,
            "detail=\(detail, privacy: .public)"
        )
    }

    @discardableResult
    static func event(_ operation: Operation, label: String = "", detail: String = "") -> Bool {
        signposter.emitEvent(
            operation.name,
            "label=\(label, privacy: .public) detail=\(detail, privacy: .public)"
        )
        return true
    }

    static func measure<T>(_ operation: Operation, label: String = "", detail: String = "", _ body: () throws -> T) rethrows -> T {
        let interval = begin(operation, label: label, detail: detail)
        defer { end(interval) }
        return try body()
    }

    static func measureAsync<T>(_ operation: Operation, label: String = "", detail: String = "", _ body: () async throws -> T) async rethrows -> T {
        let interval = begin(operation, label: label, detail: detail)
        defer { end(interval) }
        return try await body()
    }
    #else
    @discardableResult
    static func begin(_ operation: Operation, label: String = "", detail: String = "") -> Interval {
        Interval()
    }

    static func end(_ interval: Interval, detail: String = "") {}

    @discardableResult
    static func event(_ operation: Operation, label: String = "", detail: String = "") -> Bool {
        true
    }

    static func measure<T>(_ operation: Operation, label: String = "", detail: String = "", _ body: () throws -> T) rethrows -> T {
        try body()
    }

    static func measureAsync<T>(_ operation: Operation, label: String = "", detail: String = "", _ body: () async throws -> T) async rethrows -> T {
        try await body()
    }
    #endif

    @discardableResult
    static func routeTransition(from: String, to: String, reason: String = "") -> Interval {
        begin(.routeTransition, label: "\(from)->\(to)", detail: reason)
    }

    @discardableResult
    static func wardrobeRebuild(count: Int, reason: String = "") -> Interval {
        begin(.wardrobeRebuild, label: "count=\(count)", detail: reason)
    }

    @discardableResult
    static func depositUpdate(count: Int, reason: String = "") -> Interval {
        begin(.depositUpdate, label: "count=\(count)", detail: reason)
    }

    @discardableResult
    static func monthStats(month: String, itemCount: Int) -> Interval {
        begin(.monthStats, label: month, detail: "items=\(itemCount)")
    }
}
