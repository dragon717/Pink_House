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
