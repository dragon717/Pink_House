//
//  Logger.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import Foundation
import os

struct AppLogger {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pinkhouse.itemmanager", category: "General")
    
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
