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
