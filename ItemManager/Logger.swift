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
