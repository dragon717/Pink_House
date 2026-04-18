import Foundation
import os

enum IAPDiagnosticCategory: String, Codable {
    case flow = "IAPFlow"
    case balance = "IAPBalance"
    case cloudSync = "IAPCloudSync"
}

enum IAPDiagnosticLevel: String, Codable {
    case info
    case notice
    case error
}

struct IAPDiagnosticEvent: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let category: IAPDiagnosticCategory
    let name: String
    let level: IAPDiagnosticLevel
    let attemptID: String?
    let productID: String?
    let transactionID: String?
    let fields: [String: String]

    var fieldsSummary: String {
        fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " | ")
    }
}

actor IAPDiagnosticStore {
    static let shared = IAPDiagnosticStore()

    private let maxEventCount = 400
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var events: [IAPDiagnosticEvent] = []

    private init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        loadPersistedEvents()
    }

    nonisolated static func makeAttemptID() -> String {
        UUID().uuidString
    }

    func record(
        category: IAPDiagnosticCategory,
        name: String,
        level: IAPDiagnosticLevel = .info,
        attemptID: String? = nil,
        productID: String? = nil,
        transactionID: String? = nil,
        fields: [String: String] = [:]
    ) {
        var mergedFields = Self.baseFields()
        for (key, value) in fields where !value.isEmpty {
            mergedFields[key] = value
        }

        let event = IAPDiagnosticEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            category: category,
            name: name,
            level: level,
            attemptID: attemptID,
            productID: productID,
            transactionID: transactionID,
            fields: mergedFields
        )

        events.append(event)
        if events.count > maxEventCount {
            events.removeFirst(events.count - maxEventCount)
        }

        persistEvents()
        logToUnifiedLogging(event)
    }

    func exportSnapshot() throws -> URL {
        let exportDirectory = try ensureDiagnosticsDirectory()
        let timestamp = Self.exportTimestampFormatter.string(from: Date())
        let exportURL = exportDirectory.appendingPathComponent("iap_diagnostics_export_\(timestamp).jsonl")
        let event = IAPDiagnosticEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            category: .flow,
            name: "diagnostics_export_requested",
            level: .notice,
            attemptID: nil,
            productID: nil,
            transactionID: nil,
            fields: Self.baseFields()
        )
        events.append(event)
        if events.count > maxEventCount {
            events.removeFirst(events.count - maxEventCount)
        }
        persistEvents()
        logToUnifiedLogging(event)

        let contents = events.compactMap { event -> String? in
            guard let data = try? encoder.encode(event) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")

        try contents.write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }

    private func loadPersistedEvents() {
        guard let url = try? persistentLogURL() else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let content = String(data: data, encoding: .utf8) else { return }

        events = content
            .split(separator: "\n")
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(IAPDiagnosticEvent.self, from: data)
            }

        if events.count > maxEventCount {
            events = Array(events.suffix(maxEventCount))
        }
    }

    private func persistEvents() {
        do {
            let contents = events.compactMap { event -> String? in
                guard let data = try? encoder.encode(event) else { return nil }
                return String(data: data, encoding: .utf8)
            }.joined(separator: "\n")

            try contents.write(to: persistentLogURL(), atomically: true, encoding: .utf8)
        } catch {
            AppLogger.category("IAPFlow").error("Failed to persist IAP diagnostics: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func logToUnifiedLogging(_ event: IAPDiagnosticEvent) {
        let logger = AppLogger.category(event.category.rawValue)
        let summary = event.fieldsSummary
        let attempt = event.attemptID ?? "-"
        let product = event.productID ?? "-"
        let transaction = event.transactionID ?? "-"

        switch event.level {
        case .info:
            logger.info("event=\(event.name, privacy: .public) attemptID=\(attempt, privacy: .private) productID=\(product, privacy: .private) transactionID=\(transaction, privacy: .private) details=\(summary, privacy: .private)")
        case .notice:
            logger.notice("event=\(event.name, privacy: .public) attemptID=\(attempt, privacy: .private) productID=\(product, privacy: .private) transactionID=\(transaction, privacy: .private) details=\(summary, privacy: .private)")
        case .error:
            logger.error("event=\(event.name, privacy: .public) attemptID=\(attempt, privacy: .private) productID=\(product, privacy: .private) transactionID=\(transaction, privacy: .private) details=\(summary, privacy: .private)")
        }
    }

    private func ensureDiagnosticsDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func persistentLogURL() throws -> URL {
        let directory = try ensureDiagnosticsDirectory()
        return directory.appendingPathComponent("iap_diagnostics.jsonl")
    }

    private static func baseFields() -> [String: String] {
        [
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown"
        ]
    }

    private static let exportTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
