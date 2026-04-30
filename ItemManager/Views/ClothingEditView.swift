//
//  ClothingEditView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Foundation
import Combine

// MARK: - 标签数据（用于草稿保存）
struct TagData: Codable {
    let id: UUID
    let name: String
    let colorHex: String

    init(from tag: Tag) {
        self.id = tag.id
        self.name = tag.name
        self.colorHex = tag.colorHex
    }

    init(id: UUID, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

// MARK: - 编辑草稿数据结构
struct ClothingEditDraft: Codable {
    let id: UUID
    let name: String
    let brandName: String
    let types: String
    let colors: String
    let sizes: String
    let length: String
    let condition: String
    let accessories: String
    let imagePaths: [String]
    let isShared: Bool
    let originalPrice: Double
    let originalPriceJPY: Double?      // v1.11+ 原价日元，旧草稿可能不存在
    let originalPriceCurrencyCode: String? // v1.11+ 原价显示币种，旧草稿默认 CNY
    let priceTotal: Double
    let deposit: Double
    let balance: Double
    let accessoriesPrice: Double
    let shippingFee: Double?           // v1.11+ 邮费人民币，旧草稿默认 0
    let shippingFeeJPY: Double?        // v1.11+ 邮费日元，旧草稿默认 0
    let shippingFeeCurrencyCode: String? // v1.11+ 邮费显示币种，旧草稿默认 CNY
    let stock: Int
    let purchaseDate: Date
    let depositDate: Date
    let isDepositPlan: Bool
    let finalPaymentDate: Date
    let finalPaymentEndDate: Date
    let note: String
    let accessoryList: [AccessoryItemData]
    let sizeChartImagePath: String?  // 尺码表图片路径
    let priceChartImagePath: String? // 价格表图片路径
    let selectedTags: [TagData]      // 选中的标签
    let timestamp: Date

    init(id: UUID = UUID(),
         name: String,
         brandName: String,
         types: String,
         colors: String,
         sizes: String,
         length: String,
         condition: String,
         accessories: String,
         imagePaths: [String],
         isShared: Bool,
         originalPrice: Double,
         originalPriceJPY: Double? = nil,
         originalPriceCurrencyCode: String? = nil,
         priceTotal: Double,
         deposit: Double,
         balance: Double,
         accessoriesPrice: Double,
         shippingFee: Double? = nil,
         shippingFeeJPY: Double? = nil,
         shippingFeeCurrencyCode: String? = nil,
         stock: Int,
         purchaseDate: Date,
         depositDate: Date,
         isDepositPlan: Bool,
         finalPaymentDate: Date,
         finalPaymentEndDate: Date,
         note: String,
         accessoryList: [AccessoryItemData],
         sizeChartImagePath: String? = nil,
         priceChartImagePath: String? = nil,
         selectedTags: [TagData] = []) {
        self.id = id
        self.name = name
        self.brandName = brandName
        self.types = types
        self.colors = colors
        self.sizes = sizes
        self.length = length
        self.condition = condition
        self.accessories = accessories
        self.imagePaths = imagePaths
        self.isShared = isShared
        self.originalPrice = originalPrice
        self.originalPriceJPY = originalPriceJPY
        self.originalPriceCurrencyCode = originalPriceCurrencyCode
        self.priceTotal = priceTotal
        self.deposit = deposit
        self.balance = balance
        self.accessoriesPrice = accessoriesPrice
        self.shippingFee = shippingFee
        self.shippingFeeJPY = shippingFeeJPY
        self.shippingFeeCurrencyCode = shippingFeeCurrencyCode
        self.stock = stock
        self.purchaseDate = purchaseDate
        self.depositDate = depositDate
        self.isDepositPlan = isDepositPlan
        self.finalPaymentDate = finalPaymentDate
        self.finalPaymentEndDate = finalPaymentEndDate
        self.note = note
        self.accessoryList = accessoryList
        self.sizeChartImagePath = sizeChartImagePath
        self.priceChartImagePath = priceChartImagePath
        self.selectedTags = selectedTags
        self.timestamp = Date()
    }

    var hasMeaningfulData: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !types.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !colors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !sizes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !imagePaths.isEmpty ||
        originalPrice > 0 ||
        (originalPriceJPY ?? 0) > 0 ||
        priceTotal > 0 ||
        deposit > 0 ||
        balance > 0 ||
        (shippingFee ?? 0) > 0 ||
        (shippingFeeJPY ?? 0) > 0 ||
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !accessoryList.isEmpty ||
        !selectedTags.isEmpty ||
        !(sizeChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(priceChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

private enum ClothingDraftScope: Hashable, Sendable {
    case create
    case edit(UUID)

    var key: String {
        switch self {
        case .create:
            return "create"
        case .edit(let clothingID):
            return "edit.\(clothingID.uuidString)"
        }
    }

    var signpostScope: String {
        switch self {
        case .create:
            return "create"
        case .edit:
            return "edit"
        }
    }
}

private struct ClothingDraftIndex: Codable {
    var createModifiedAt: Date?
    var editingModifiedAtByID: [String: Date] = [:]
}

private final class ClothingDraftFileStore {
    static let shared = ClothingDraftFileStore()

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private var draftsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("ItemManager", isDirectory: true)
            .appendingPathComponent("Drafts", isDirectory: true)
    }

    private var editDirectory: URL {
        draftsDirectory.appendingPathComponent("edit", isDirectory: true)
    }

    private var indexURL: URL {
        draftsDirectory.appendingPathComponent("_index.json", isDirectory: false)
    }

    private var createDraftURL: URL {
        draftsDirectory.appendingPathComponent("create.json", isDirectory: false)
    }

    func hasCreateDraft() -> Bool {
        fileManager.fileExists(atPath: createDraftURL.path)
    }

    func loadCreateDraft() throws -> ClothingEditDraft? {
        try loadDraft(from: createDraftURL)
    }

    func loadEditingDraft(for clothingID: UUID) throws -> ClothingEditDraft? {
        try loadDraft(from: editDraftURL(for: clothingID))
    }

    @discardableResult
    func saveCreateDraft(_ draft: ClothingEditDraft) throws -> Int {
        try saveDraft(draft, scope: .create)
    }

    @discardableResult
    func saveEditingDraft(_ draft: ClothingEditDraft, for clothingID: UUID) throws -> Int {
        try saveDraft(draft, scope: .edit(clothingID))
    }

    func clearCreateDraft() throws {
        if fileManager.fileExists(atPath: createDraftURL.path) {
            try fileManager.removeItem(at: createDraftURL)
        }
        var index = loadIndex()
        index.createModifiedAt = nil
        try saveIndex(index)
    }

    func clearEditingDraft(for clothingID: UUID) throws {
        let url = editDraftURL(for: clothingID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        var index = loadIndex()
        index.editingModifiedAtByID.removeValue(forKey: clothingID.uuidString)
        try saveIndex(index)
    }

    private func loadDraft(from url: URL) throws -> ClothingEditDraft? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(ClothingEditDraft.self, from: data)
    }

    @discardableResult
    private func saveDraft(_ draft: ClothingEditDraft, scope: ClothingDraftScope) throws -> Int {
        try ensureDirectories()
        let data = try encoder.encode(draft)
        let targetURL = draftURL(for: scope)
        try data.write(to: targetURL, options: [.atomic])

        var index = loadIndex()
        switch scope {
        case .create:
            index.createModifiedAt = Date()
        case .edit(let clothingID):
            index.editingModifiedAtByID[clothingID.uuidString] = Date()
        }
        try saveIndex(index)
        return data.count
    }

    private func draftURL(for scope: ClothingDraftScope) -> URL {
        switch scope {
        case .create:
            return createDraftURL
        case .edit(let clothingID):
            return editDraftURL(for: clothingID)
        }
    }

    private func editDraftURL(for clothingID: UUID) -> URL {
        editDirectory.appendingPathComponent("\(clothingID.uuidString).json", isDirectory: false)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: editDirectory, withIntermediateDirectories: true)
    }

    private func loadIndex() -> ClothingDraftIndex {
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let index = try? decoder.decode(ClothingDraftIndex.self, from: data)
        else {
            return ClothingDraftIndex()
        }
        return index
    }

    private func saveIndex(_ index: ClothingDraftIndex) throws {
        try ensureDirectories()
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: [.atomic])
    }
}

private struct ClothingDraftSaveRequest: Sendable {
    let draft: ClothingEditDraft
    let scope: ClothingDraftScope
    let reason: String
}

private actor DraftPersistor {
    static let shared = DraftPersistor(fileStore: .shared)

    private let fileStore: ClothingDraftFileStore
    private var pendingRequests: [String: ClothingDraftSaveRequest] = [:]
    private var pendingTasks: [String: Task<Void, Never>] = [:]

    init(fileStore: ClothingDraftFileStore) {
        self.fileStore = fileStore
    }

    func enqueueSave(_ draft: ClothingEditDraft, scope: ClothingDraftScope, reason: String) {
        let request = ClothingDraftSaveRequest(draft: draft, scope: scope, reason: reason)
        let key = scope.key
        pendingRequests[key] = request
        pendingTasks[key]?.cancel()
        pendingTasks[key] = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            await self.flushPendingSave(for: key)
        }
    }

    func flushNow(_ draft: ClothingEditDraft, scope: ClothingDraftScope, reason: String) {
        let key = scope.key
        pendingTasks[key]?.cancel()
        pendingTasks[key] = nil
        pendingRequests[key] = nil
        persist(ClothingDraftSaveRequest(draft: draft, scope: scope, reason: reason))
    }

    func clear(scope: ClothingDraftScope) {
        let key = scope.key
        pendingTasks[key]?.cancel()
        pendingTasks[key] = nil
        pendingRequests[key] = nil

        do {
            switch scope {
            case .create:
                try fileStore.clearCreateDraft()
            case .edit(let clothingID):
                try fileStore.clearEditingDraft(for: clothingID)
            }
        } catch {
            AppLogger.error("DraftReliability: Failed to clear file draft for \(scope.key): \(error)")
        }
    }

    private func flushPendingSave(for key: String) {
        pendingTasks[key] = nil
        guard let request = pendingRequests.removeValue(forKey: key) else { return }
        persist(request)
    }

    private func persist(_ request: ClothingDraftSaveRequest) {
        do {
            let byteSize: Int
            switch request.scope {
            case .create:
                byteSize = try fileStore.saveCreateDraft(request.draft)
            case .edit(let clothingID):
                byteSize = try fileStore.saveEditingDraft(request.draft, for: clothingID)
            }
            DraftReliabilitySignpost.draftSave(
                scope: request.scope.signpostScope,
                draftID: request.draft.id,
                imageCount: request.draft.imagePaths.count,
                tagCount: request.draft.selectedTags.count,
                byteSize: byteSize,
                reason: "file:\(request.reason)"
            )
        } catch {
            DraftReliabilitySignpost.draftSaveFailed(scope: request.scope.signpostScope, error: error)
            AppLogger.error("DraftReliability: Failed to persist file draft for \(request.scope.key): \(error)")
        }
    }
}

// MARK: - 草稿管理器
final class ClothingEditDraftManager: ObservableObject {
    static let shared = ClothingEditDraftManager()

    private let userDefaults = UserDefaults.standard
    private let draftKey = "ClothingEditDraft"
    private let draftIDKey = "ClothingEditDraftID"
    private let editingDraftKeyPrefix = "ClothingEditDraft.edit."

    // 当前新建状态（用于前后台/失活时保存）
    @Published var currentDraft: ClothingEditDraft?
    @Published private(set) var hasPersistedDraft: Bool
    private var currentEditingDrafts: [UUID: ClothingEditDraft] = [:]
    private var activeEditorTokens: Set<UUID> = []

    var hasActiveEditor: Bool {
        !activeEditorTokens.isEmpty
    }

    private init() {
        hasPersistedDraft = userDefaults.data(forKey: draftKey) != nil
        // 监听应用进入后台通知
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("DraftManager: Background notification received")
            self?.persistActiveDrafts(reason: "didEnterBackgroundNotification")
        }
    }

    func registerActiveEditor(_ token: UUID) {
        activeEditorTokens.insert(token)
        print("DraftManager: Active editor registered, count: \(activeEditorTokens.count)")
    }

    func unregisterActiveEditor(_ token: UUID) {
        activeEditorTokens.remove(token)
        print("DraftManager: Active editor unregistered, count: \(activeEditorTokens.count)")
    }

    func saveDraft(_ draft: ClothingEditDraft, reason: String = "direct") {
        print("DraftManager: Saving draft with ID: \(draft.id), images: \(draft.imagePaths.count)")
        currentDraft = draft
        do {
            let data = try JSONEncoder().encode(draft)
            userDefaults.set(data, forKey: draftKey)
            userDefaults.set(draft.id.uuidString, forKey: draftIDKey)
            userDefaults.synchronize()
            hasPersistedDraft = true
            DraftReliabilitySignpost.draftSave(
                scope: "create",
                draftID: draft.id,
                imageCount: draft.imagePaths.count,
                tagCount: draft.selectedTags.count,
                byteSize: data.count,
                reason: reason
            )
            print("DraftManager: Draft saved successfully")
        } catch {
            DraftReliabilitySignpost.draftSaveFailed(scope: "create", error: error)
            AppLogger.error("DraftReliability: Failed to encode create draft: \(error)")
            print("DraftManager: Failed to encode draft: \(error)")
        }
    }

    func loadDraft() -> ClothingEditDraft? {
        guard let data = userDefaults.data(forKey: draftKey) else {
            print("DraftManager: No draft data found in UserDefaults")
            DraftReliabilitySignpost.draftLoad(scope: "create", source: "none", draftID: nil, imageCount: 0)
            return nil
        }
        do {
            let draft = try JSONDecoder().decode(ClothingEditDraft.self, from: data)
            DraftReliabilitySignpost.draftLoad(scope: "create", source: "userdefaults_persisted", draftID: draft.id, imageCount: draft.imagePaths.count)
            print("DraftManager: Loaded draft with ID: \(draft.id), images: \(draft.imagePaths.count)")
            return draft
        } catch {
            DraftReliabilitySignpost.draftLoad(scope: "create", source: "decode_failed", draftID: nil, imageCount: 0)
            AppLogger.error("DraftReliability: Failed to decode create draft: \(error)")
            print("DraftManager: Failed to decode draft data: \(error)")
            return nil
        }
    }

    func loadDraftID() -> UUID? {
        guard let idString = userDefaults.string(forKey: draftIDKey) else {
            print("DraftManager: No draftID found in UserDefaults")
            return nil
        }
        guard let uuid = UUID(uuidString: idString) else {
            print("DraftManager: Failed to parse draftID: \(idString)")
            return nil
        }
        print("DraftManager: Loaded draftID: \(uuid)")
        return uuid
    }

    func clearDraft() {
        print("DraftManager: Clearing draft")
        currentDraft = nil
        userDefaults.removeObject(forKey: draftKey)
        userDefaults.removeObject(forKey: draftIDKey)
        userDefaults.synchronize()
        hasPersistedDraft = false
        DraftReliabilitySignpost.draftClear(scope: "create", reason: "clearDraft")
        print("DraftManager: Draft cleared")
    }

    func hasDraft() -> Bool {
        hasPersistedDraft
    }

    func refreshDraftPresence() {
        hasPersistedDraft = userDefaults.data(forKey: draftKey) != nil
    }

    func updateEditingDraft(_ draft: ClothingEditDraft, for clothingID: UUID) {
        currentEditingDrafts[clothingID] = draft
        print("DraftManager: Updated editing draft for clothing: \(clothingID), images: \(draft.imagePaths.count)")
    }

    func saveEditingDraft(_ draft: ClothingEditDraft, for clothingID: UUID, reason: String = "direct") {
        currentEditingDrafts[clothingID] = draft
        print("DraftManager: Saving editing draft for clothing: \(clothingID), images: \(draft.imagePaths.count)")
        do {
            let data = try JSONEncoder().encode(draft)
            userDefaults.set(data, forKey: editingDraftKey(for: clothingID))
            userDefaults.synchronize()
            DraftReliabilitySignpost.draftSave(
                scope: "edit",
                draftID: draft.id,
                imageCount: draft.imagePaths.count,
                tagCount: draft.selectedTags.count,
                byteSize: data.count,
                reason: "\(reason):\(clothingID.uuidString)"
            )
            print("DraftManager: Editing draft saved successfully")
        } catch {
            DraftReliabilitySignpost.draftSaveFailed(scope: "edit:\(clothingID.uuidString)", error: error)
            AppLogger.error("DraftReliability: Failed to encode editing draft for \(clothingID): \(error)")
            print("DraftManager: Failed to encode editing draft: \(error)")
        }
    }

    func loadEditingDraft(for clothingID: UUID) -> ClothingEditDraft? {
        if let draft = currentEditingDrafts[clothingID] {
            print("DraftManager: Loaded in-memory editing draft for clothing: \(clothingID), images: \(draft.imagePaths.count)")
            DraftReliabilitySignpost.draftLoad(scope: "edit", source: "memory_currentDraft", draftID: draft.id, imageCount: draft.imagePaths.count)
            return draft
        }

        guard let data = userDefaults.data(forKey: editingDraftKey(for: clothingID)) else {
            print("DraftManager: No editing draft found for clothing: \(clothingID)")
            DraftReliabilitySignpost.draftLoad(scope: "edit", source: "none", draftID: nil, imageCount: 0)
            return nil
        }
        do {
            let draft = try JSONDecoder().decode(ClothingEditDraft.self, from: data)
            currentEditingDrafts[clothingID] = draft
            DraftReliabilitySignpost.draftLoad(scope: "edit", source: "userdefaults_editing", draftID: draft.id, imageCount: draft.imagePaths.count)
            print("DraftManager: Loaded persisted editing draft for clothing: \(clothingID), images: \(draft.imagePaths.count)")
            return draft
        } catch {
            DraftReliabilitySignpost.draftLoad(scope: "edit", source: "decode_failed", draftID: nil, imageCount: 0)
            AppLogger.error("DraftReliability: Failed to decode editing draft for \(clothingID): \(error)")
            print("DraftManager: Failed to decode editing draft for clothing: \(clothingID): \(error)")
            return nil
        }
    }

    func clearEditingDraft(for clothingID: UUID) {
        print("DraftManager: Clearing editing draft for clothing: \(clothingID)")
        currentEditingDrafts.removeValue(forKey: clothingID)
        userDefaults.removeObject(forKey: editingDraftKey(for: clothingID))
        userDefaults.synchronize()
        DraftReliabilitySignpost.draftClear(scope: "edit", reason: clothingID.uuidString)
        print("DraftManager: Editing draft cleared")
    }

    func persistActiveDrafts(reason: String) {
        if let draft = currentDraft {
            if draft.hasMeaningfulData {
                print("DraftManager: Persisting current new draft, reason: \(reason), images: \(draft.imagePaths.count)")
                saveDraft(draft, reason: reason)
            } else {
                print("DraftManager: Skip empty current new draft, reason: \(reason)")
            }
        } else {
            print("DraftManager: No current new draft to persist, reason: \(reason)")
        }

        let editingDraftsToPersist = currentEditingDrafts
        for (clothingID, draft) in editingDraftsToPersist {
            print("DraftManager: Persisting editing draft, reason: \(reason), clothing: \(clothingID)")
            saveEditingDraft(draft, for: clothingID, reason: reason)
        }
    }

    private func editingDraftKey(for clothingID: UUID) -> String {
        "\(editingDraftKeyPrefix)\(clothingID.uuidString)"
    }
}

struct ClothingEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    // 统一使用 deletedAt == nil 作为未删除的判断条件，与其他视图保持一致
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothings: [Clothing]
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    @ObservedObject private var draftManager = ClothingEditDraftManager.shared

    @State private var clothing: Clothing?
    @State private var draftID: UUID = UUID()

    // Form States
    @State private var name: String = ""
    @State private var brandName: String = ""
    @State private var types: String = ""
    @State private var colors: String = ""
    @State private var sizes: String = ""
    @State private var length: String = ""
    @State private var condition: String = "全新"
    @State private var accessories: String = ""
    @State private var imagePaths: [String] = []
    @State private var isShared: Bool = false

    // 表图字段
    @State private var sizeChartImagePath: String? = nil
    @State private var priceChartImagePath: String? = nil

    // Tag States
    @State private var showingAddTagSheet = false
    @State private var selectedTags: [Tag] = []

    // Price States
    @State private var originalPrice: Double = 0.0
    @State private var originalPriceJPY: Double = 0.0
    @State private var originalPriceCurrency: ClothingPriceCurrency = .cny
    @State private var originalPriceRateUpdatedAt: Date? = nil
    @State private var priceTotal: Double = 0.0
    @State private var deposit: Double = 0.0
    @State private var balance: Double = 0.0
    @State private var accessoriesPrice: Double = 0.0
    @State private var shippingFee: Double = 0.0
    @State private var shippingFeeJPY: Double = 0.0
    @State private var shippingFeeCurrency: ClothingPriceCurrency = .cny
    @State private var shippingRateUpdatedAt: Date? = nil
    @State private var jpyExchangeRate: Double = CurrencyExchangeRateService.defaultJPYRate
    @State private var stock: Int = 1

    // Selection Sheets
    @State private var showingBrandSelection = false
    @State private var tempSelectedBrand: Brand?
    @State private var activeSelectionField: ClothingField?
    @State private var showingGenericSelection = false

    // Custom Accessories
    @State private var accessoryList: [AccessoryItemData] = []

    // Purchase States
    @State private var purchaseDate: Date = Date()
    @State private var depositDate: Date = Date()
    @State private var isDepositPlan: Bool = false
    @State private var finalPaymentDate: Date = Date()
    @State private var finalPaymentEndDate: Date = Date()
    @State private var note: String = ""

    // 标记是否是通过"保存"按钮离开的
    @State private var isSaving = false
    @State private var isCancelling = false

    // 标记是否从草稿继续（false表示新建，清除草稿）
    private var continueFromDraft: Bool

    // 标记是否已经处理过草稿逻辑（防止onAppear多次执行）
    @State private var hasProcessedDraft = false

    // 标记是否已经因前后台/失活持久化过（避免onDisappear重复保存草稿）
    @State private var didPersistForLifecycle = false
    @State private var editorSessionID = UUID()
    @State private var hasUserTouchedAnyField = false
    @State private var isReadyForUserDraftChanges = false
    @State private var pendingDraftSaveTask: Task<Void, Never>?
    @State private var suppressNextDraftObservationAsSystemChange = false
    @State private var programmaticDraftObservationKey: DraftObservationKey?

    // Toast 提示状态
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastType = .error

    // Toast 类型
    enum ToastType {
        case success, error, warning

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            }
        }
    }

    private var initialBrandID: UUID?
    private var initialTypes: Set<String>?

    init(clothing: Clothing?, initialBrandID: UUID? = nil, initialTypes: Set<String>? = nil, continueFromDraft: Bool = true) {
        _clothing = State(initialValue: clothing)
        self.initialBrandID = initialBrandID
        self.initialTypes = initialTypes
        self.continueFromDraft = continueFromDraft
        print("ClothingEditView: INIT called, isEditing: \(clothing != nil), continueFromDraft: \(continueFromDraft)")
    }

    var isEditing: Bool { clothing != nil }

    private var containerPalette: AdaptivePaletteV2 {
        themeManager.getPaletteForContainer(
            containerBackground: .ultraThinMaterial,
            colorScheme: colorScheme
        )
    }

    // 提取基础信息视图，避免 body 中表达式过于复杂
    private var basicInfoSection: some View {
        ClothingBasicInfoView(
            imagePaths: $imagePaths,
            name: $name,
            brandName: $brandName,
            isShared: $isShared,
            types: $types,
            colors: $colors,
            sizes: $sizes,
            length: $length,
            condition: $condition,
            accessories: $accessories,
            sizeChartImagePath: $sizeChartImagePath,
            deleteChartFileImmediately: !isEditing,
            showingBrandSelection: $showingBrandSelection,
            showingGenericSelection: $showingGenericSelection,
            activeSelectionField: $activeSelectionField
        )
    }

    // 提取标签视图
    private var tagsSection: some View {
        ClothingTagsView(
            selectedTags: $selectedTags,
            showingAddTagSheet: $showingAddTagSheet
        )
    }

    // 提取价格视图
    private var priceSection: some View {
        ClothingPriceView(
            originalPrice: $originalPrice,
            originalPriceJPY: $originalPriceJPY,
            originalPriceCurrency: $originalPriceCurrency,
            priceTotal: $priceTotal,
            deposit: $deposit,
            balance: $balance,
            accessoriesPrice: $accessoriesPrice,
            shippingFee: $shippingFee,
            shippingFeeJPY: $shippingFeeJPY,
            shippingFeeCurrency: $shippingFeeCurrency,
            stock: $stock,
            accessoryList: $accessoryList,
            jpyExchangeRate: jpyExchangeRate,
            priceChartImagePath: $priceChartImagePath,
            deleteChartFileImmediately: !isEditing,
            onShowToast: handleShowToast
        )
    }

    private var selectedTagIDs: [UUID] {
        selectedTags.map(\.id)
    }

    private struct DraftObservationKey: Equatable {
        let name: String
        let brandName: String
        let types: String
        let colors: String
        let sizes: String
        let length: String
        let condition: String
        let accessories: String
        let isShared: Bool
        let originalPrice: Double
        let originalPriceJPY: Double
        let originalPriceCurrency: ClothingPriceCurrency
        let priceTotal: Double
        let deposit: Double
        let balance: Double
        let accessoriesPrice: Double
        let shippingFee: Double
        let shippingFeeJPY: Double
        let shippingFeeCurrency: ClothingPriceCurrency
        let stock: Int
        let purchaseDate: Date
        let depositDate: Date
        let isDepositPlan: Bool
        let finalPaymentDate: Date
        let finalPaymentEndDate: Date
        let note: String
        let accessoryList: [AccessoryItemData]
        let selectedTagIDs: [UUID]
        let sizeChartImagePath: String?
        let priceChartImagePath: String?
    }

    private var draftObservationKey: DraftObservationKey {
        DraftObservationKey(
            name: name,
            brandName: brandName,
            types: types,
            colors: colors,
            sizes: sizes,
            length: length,
            condition: condition,
            accessories: accessories,
            isShared: isShared,
            originalPrice: originalPrice,
            originalPriceJPY: originalPriceJPY,
            originalPriceCurrency: originalPriceCurrency,
            priceTotal: priceTotal,
            deposit: deposit,
            balance: balance,
            accessoriesPrice: accessoriesPrice,
            shippingFee: shippingFee,
            shippingFeeJPY: shippingFeeJPY,
            shippingFeeCurrency: shippingFeeCurrency,
            stock: stock,
            purchaseDate: purchaseDate,
            depositDate: depositDate,
            isDepositPlan: isDepositPlan,
            finalPaymentDate: finalPaymentDate,
            finalPaymentEndDate: finalPaymentEndDate,
            note: note,
            accessoryList: accessoryList,
            selectedTagIDs: selectedTagIDs,
            sizeChartImagePath: sizeChartImagePath,
            priceChartImagePath: priceChartImagePath
        )
    }

    // 提取购买信息视图
    private var purchaseInfoSection: some View {
        ClothingPurchaseInfoView(
            purchaseDate: $purchaseDate,
            depositDate: $depositDate,
            isDepositPlan: $isDepositPlan,
            finalPaymentDate: $finalPaymentDate,
            finalPaymentEndDate: $finalPaymentEndDate,
            note: $note
        )
    }

    // 处理 Toast 显示的回调
    private func handleShowToast(message: String, type: ClothingPriceView.ToastType) {
        let toastType: ToastType
        switch type {
        case .success: toastType = .success
        case .error: toastType = .error
        case .warning: toastType = .warning
        }
        showToastMessage(message, type: toastType)
    }

    var body: some View {
        ZStack {
            // Background
            LiquidBackground()
                .ignoresSafeArea()
                .environment(\.containerPalette, containerPalette)

            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - 裙装信息
                    basicInfoSection

                    // MARK: - 标签分类
                    tagsSection

                    // MARK: - 价格信息
                    priceSection

                    // MARK: - 购买信息
                    purchaseInfoSection
                }
                .padding()
            }

            // Toast 提示层
            toastOverlay
        }
        .navigationTitle(isEditing ? "编辑" : "手动创建")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    cancelPendingDraftSave()
                    isCancelling = true
                    // 取消时如果有有效信息或用户碰过任一字段，则保存草稿，方便用户下次恢复。
                    // 注意：创建模式取消不再清理 UserDefaults 草稿；只有“手动创建”入口负责清旧草稿。
                    if !isEditing {
                        if shouldKeepCreateDraft {
                            print("ClothingEditView: Cancel create with draft-worthy data, saving draft")
                            saveCurrentStateAsDraft(reason: "cancel-create")
                        } else {
                            print("ClothingEditView: Cancel empty untouched create form, keeping existing draft state unchanged")
                        }
                    } else if let clothingID = clothing?.id {
                        draftManager.clearEditingDraft(for: clothingID)
                    }
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    cancelPendingDraftSave()
                    // 标记为保存操作
                    isSaving = true
                    // 保存前清除草稿
                    clearCurrentDraftStorage()
                    save()
                }
                .disabled(name.isEmpty)
            }
        }
        .sheet(isPresented: $showingBrandSelection) {
            BrandSelectionView(selectedBrand: $tempSelectedBrand)
        }
        .onChange(of: tempSelectedBrand) { _, newValue in
            if let brand = newValue {
                brandName = brand.name
            }
        }
        .sheet(isPresented: $showingAddTagSheet) {
            TagSelectionView(selectedTags: $selectedTags)
        }
        .sheet(isPresented: $showingGenericSelection) {
            if let field = activeSelectionField {
                SimpleStringSelectionView(
                    title: "选择\(field.rawValue)",
                    options: getAllOptions(for: field),
                    allowMultiple: isMultiSelect(field),
                    selection: binding(for: field)
                )
            }
        }
        .onAppear {
            DraftReliabilitySignpost.editorInit(isEditing: isEditing, continueFromDraft: continueFromDraft, sessionID: editorSessionID)
            draftManager.registerActiveEditor(editorSessionID)
            initializeEditorIfNeeded()
            Task { await refreshJPYRateForEditor() }
        }
        .onChange(of: imagePaths) { oldValue, newValue in
            print("ClothingEditView: imagePaths changed from \(oldValue.count) to \(newValue.count) images")
            didPersistForLifecycle = false
            if isReadyForUserDraftChanges {
                hasUserTouchedAnyField = true
            }
            // 更新当前草稿到管理器
            updateCurrentDraft()
            // 图片变化后立即保存草稿到磁盘，防止丢失
            if !isEditing {
                print("ClothingEditView: Image paths changed, immediately saving draft to disk")
                saveCurrentStateAsDraft(reason: "imagePaths")
            } else {
                saveCurrentStateAsDraft(reason: "imagePaths")
            }
        }
        .onChange(of: draftObservationKey) { oldValue, newValue in
            didPersistForLifecycle = false
            updateCurrentDraft()
            if let programmaticKey = programmaticDraftObservationKey {
                programmaticDraftObservationKey = nil
                if newValue == programmaticKey {
                    print("ClothingEditView: Draft observation changed from initial restore, not marking as user touch")
                    return
                }
            }
            if suppressNextDraftObservationAsSystemChange {
                suppressNextDraftObservationAsSystemChange = false
                print("ClothingEditView: Draft observation changed from system sync, not marking as user touch")
                return
            }
            guard isReadyForUserDraftChanges else {
                print("ClothingEditView: Draft observation changed during initialization, not marking as user touch")
                return
            }
            hasUserTouchedAnyField = true
            let chartChanged =
                oldValue.sizeChartImagePath != newValue.sizeChartImagePath ||
                oldValue.priceChartImagePath != newValue.priceChartImagePath
            if chartChanged {
                cancelPendingDraftSave()
                saveCurrentStateAsDraft(reason: "chart-change")
            } else {
                scheduleDebouncedDraftSave(reason: "field-change")
            }
        }
        .onChange(of: jpyExchangeRate) { _, _ in
            let previousObservationKey = draftObservationKey
            suppressNextDraftObservationAsSystemChange = true
            syncCurrencyAmountsFromPreferredCurrency()
            if previousObservationKey == draftObservationKey {
                suppressNextDraftObservationAsSystemChange = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            DraftReliabilitySignpost.scenePhase("\(newPhase)", reason: "scenePhase-change")
            if newPhase == .active {
                didPersistForLifecycle = false
                return
            }
            guard newPhase == .inactive || newPhase == .background else { return }
            print("ClothingEditView: scenePhase changed to \(newPhase), saving draft snapshot")
            persistCurrentStateForLifecycle(reason: "scenePhase-\(newPhase)")
        }
        // 监听应用进入后台通知，设置标记避免重复保存
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            print("ClothingEditView: App did enter background")
            DraftReliabilitySignpost.scenePhase("didEnterBackgroundNotification", reason: "notification")
            persistCurrentStateForLifecycle(reason: "didEnterBackgroundNotification")
        }
        .onDisappear {
            print("ClothingEditView: onDisappear")
            draftManager.unregisterActiveEditor(editorSessionID)
            cancelPendingDraftSave()
            // 如果不是保存/明确取消，且没有因前后台/失活保存过，则保留当前快照。
            let shouldSaveDraft = !isSaving && !isCancelling && !didPersistForLifecycle && (isEditing || shouldKeepCreateDraft)
            if shouldSaveDraft {
                print("ClothingEditView: Saving draft on disappear")
                saveCurrentStateAsDraft(reason: "onDisappear")
            } else {
                print("ClothingEditView: Not saving draft on disappear")
            }
        }
        .onChange(of: deposit) { oldValue, newValue in
            updateTotalPrice()
        }
        .onChange(of: balance) { oldValue, newValue in
            updateTotalPrice()
        }
    }

    // MARK: - Helpers

    private var shouldKeepCreateDraft: Bool {
        hasMeaningfulData() || hasUserTouchedAnyField
    }

    private func scheduleDebouncedDraftSave(reason: String) {
        cancelPendingDraftSave()
        pendingDraftSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            saveCurrentStateAsDraft(reason: reason)
            pendingDraftSaveTask = nil
        }
    }

    private func cancelPendingDraftSave() {
        pendingDraftSaveTask?.cancel()
        pendingDraftSaveTask = nil
    }

    private func initializeEditorIfNeeded() {
        print("ClothingEditView: onAppear triggered, isEditing: \(isEditing), draftID: \(draftID), continueFromDraft: \(continueFromDraft), hasProcessedDraft: \(hasProcessedDraft)")

        // 防止多次处理草稿逻辑
        guard !hasProcessedDraft else {
            print("ClothingEditView: Draft already processed, skipping")
            isReadyForUserDraftChanges = true
            return
        }
        isReadyForUserDraftChanges = false
        hasProcessedDraft = true

        // 加载自动补全数据
        SuggestionManager.shared.loadDataAndBuildIndex(modelContext: modelContext)

        if let c = clothing {
            // 编辑模式：先从数据库加载，再覆盖未保存的编辑草稿。
            loadFromClothing(c)
            if let editDraft = draftManager.loadEditingDraft(for: c.id) {
                print("ClothingEditView: Restoring editing draft for clothing: \(c.id)")
                restoreFromDraft(editDraft)
            }
        } else {
            if continueFromDraft, let persistedDraft = draftManager.loadDraft() {
                print("ClothingEditView: Found persisted draft with \(persistedDraft.imagePaths.count) images")
                restoreFromDraft(persistedDraft)
            } else if let inMemoryDraft = draftManager.currentDraft {
                // 手动创建入口会清掉旧持久草稿；这里仅恢复本次正在编辑的内存快照，
                // 避免下拉通知栏/失活导致 SwiftUI 重建后表单回到空白。
                print("ClothingEditView: Restoring in-memory draft with \(inMemoryDraft.imagePaths.count) images")
                restoreFromDraft(inMemoryDraft)
            } else {
                print("ClothingEditView: No draft found to restore")
            }
            applyInitialValuesIfNeeded()
        }

        // 更新当前草稿到管理器（用于失活/后台保存）
        updateCurrentDraft()
        hasUserTouchedAnyField = false
        programmaticDraftObservationKey = draftObservationKey
        Task { @MainActor in
            await Task.yield()
            isReadyForUserDraftChanges = true
        }
    }

    private func loadFromClothing(_ c: Clothing) {
        name = c.name
        brandName = c.brand?.name ?? ""
        types = c.types
        colors = c.colors
        sizes = c.sizes
        length = c.length
        condition = c.condition
        accessories = c.accessories
        imagePaths = c.imagePaths
        isShared = c.isShared
        originalPrice = NSDecimalNumber(decimal: c.originalPrice).doubleValue
        originalPriceJPY = NSDecimalNumber(decimal: c.originalPriceJPY).doubleValue
        originalPriceCurrency = c.originalPriceCurrency
        originalPriceRateUpdatedAt = c.originalPriceRateUpdatedAt
        shippingFee = NSDecimalNumber(decimal: c.shippingFee).doubleValue
        shippingFeeJPY = NSDecimalNumber(decimal: c.shippingFeeJPY).doubleValue
        shippingFeeCurrency = c.shippingFeeCurrency
        shippingRateUpdatedAt = c.shippingRateUpdatedAt
        jpyExchangeRate = NSDecimalNumber(decimal: c.originalPriceExchangeRateJPY).doubleValue > 0
            ? NSDecimalNumber(decimal: c.originalPriceExchangeRateJPY).doubleValue
            : CurrencyExchangeRateService.shared.cnyToJPYRate
        syncCurrencyAmountsFromPreferredCurrency()
        let depositVal = NSDecimalNumber(decimal: c.deposit).doubleValue
        let balanceVal = NSDecimalNumber(decimal: c.balance).doubleValue
        deposit = depositVal
        balance = balanceVal

        accessoriesPrice = NSDecimalNumber(decimal: c.accessoriesPrice).doubleValue

        if let items = c.accessoryItems {
            accessoryList = items.sorted(by: { $0.sortIndex < $1.sortIndex })
                .map {
                    AccessoryItemData(
                        id: UUID(),
                        name: $0.name,
                        price: NSDecimalNumber(decimal: $0.price).doubleValue,
                        deposit: NSDecimalNumber(decimal: $0.deposit).doubleValue,
                        balance: NSDecimalNumber(decimal: $0.balance).doubleValue,
                        imagePaths: $0.imagePaths
                    )
                }
        } else {
            accessoryList = []
        }

        stock = c.stock
        purchaseDate = c.purchaseDate
        depositDate = c.depositDate ?? Date()
        isDepositPlan = c.isDepositPlan
        finalPaymentDate = c.finalPaymentDate ?? Date()
        finalPaymentEndDate = c.finalPaymentEndDate ?? (c.finalPaymentDate ?? Date())
        note = c.note
        selectedTags = c.tags ?? []

        sizeChartImagePath = c.sizeChartImagePath
        priceChartImagePath = c.priceChartImagePath

        if depositVal > 0 && balanceVal > 0 {
            priceTotal = depositVal + balanceVal
        } else {
            priceTotal = NSDecimalNumber(decimal: c.price).doubleValue
        }
    }

    private func applyInitialValuesIfNeeded() {
        if brandName.isEmpty, let brandID = initialBrandID {
            let descriptor = FetchDescriptor<Brand>(predicate: #Predicate { $0.id == brandID })
            if let brand = try? modelContext.fetch(descriptor).first {
                brandName = brand.name
            }
        }

        if types.isEmpty, let initTypes = initialTypes, !initTypes.isEmpty {
            let validTypes = initTypes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if !validTypes.isEmpty {
                types = validTypes.joined(separator: ",")
            }
        }
    }

    private func makeCurrentDraft() -> ClothingEditDraft {
        let tagDataList = selectedTags.map { TagData(from: $0) }
        return ClothingEditDraft(
            id: draftID,
            name: name,
            brandName: brandName,
            types: types,
            colors: colors,
            sizes: sizes,
            length: length,
            condition: condition,
            accessories: accessories,
            imagePaths: imagePaths,
            isShared: isShared,
            originalPrice: originalPrice,
            originalPriceJPY: originalPriceJPY,
            originalPriceCurrencyCode: originalPriceCurrency.rawValue,
            priceTotal: priceTotal,
            deposit: deposit,
            balance: balance,
            accessoriesPrice: accessoriesPrice,
            shippingFee: shippingFee,
            shippingFeeJPY: shippingFeeJPY,
            shippingFeeCurrencyCode: shippingFeeCurrency.rawValue,
            stock: stock,
            purchaseDate: purchaseDate,
            depositDate: depositDate,
            isDepositPlan: isDepositPlan,
            finalPaymentDate: finalPaymentDate,
            finalPaymentEndDate: finalPaymentEndDate,
            note: note,
            accessoryList: accessoryList,
            sizeChartImagePath: sizeChartImagePath,
            priceChartImagePath: priceChartImagePath,
            selectedTags: tagDataList
        )
    }

    private func persistCurrentStateForLifecycle(reason: String) {
        cancelPendingDraftSave()
        guard !isSaving, !isCancelling else { return }
        guard isEditing || shouldKeepCreateDraft else {
            print("ClothingEditView: Skip lifecycle draft save, no meaningful data or user touch, reason: \(reason)")
            return
        }
        saveCurrentStateAsDraft(reason: reason)
        didPersistForLifecycle = true
    }

    private func clearCurrentDraftStorage() {
        if let clothingID = clothing?.id {
            draftManager.clearEditingDraft(for: clothingID)
        } else {
            draftManager.clearDraft()
        }
    }

    // 保存当前状态为草稿
    private func saveCurrentStateAsDraft(reason: String = "direct") {
        print("ClothingEditView: saveCurrentStateAsDraft called, reason: \(reason), draftID: \(draftID), imagePaths count: \(imagePaths.count), name: \(name)")
        let draft = makeCurrentDraft()
        if let clothingID = clothing?.id {
            draftManager.saveEditingDraft(draft, for: clothingID, reason: reason)
        } else {
            draftManager.saveDraft(draft, reason: reason)
        }
        print("ClothingEditView: Draft saved successfully with \(draft.imagePaths.count) images, \(draft.selectedTags.count) tags")
    }

    // 更新当前草稿到管理器（用于后台保存）
    private func updateCurrentDraft() {
        let draft = makeCurrentDraft()
        if let clothingID = clothing?.id {
            draftManager.updateEditingDraft(draft, for: clothingID)
        } else {
            draftManager.currentDraft = draft
        }
        print("ClothingEditView: Updated current draft with \(draft.imagePaths.count) images, \(draft.selectedTags.count) tags")
    }

    // 从草稿恢复状态
    private func restoreFromDraft(_ draft: ClothingEditDraft) {
        print("ClothingEditView: restoreFromDraft called, draft has \(draft.imagePaths.count) images, \(draft.selectedTags.count) tags, current has \(imagePaths.count) images")
        name = draft.name
        brandName = draft.brandName
        types = draft.types
        colors = draft.colors
        sizes = draft.sizes
        length = draft.length
        condition = draft.condition
        accessories = draft.accessories
        // 恢复图片引用 - 草稿中的图片应该被完全恢复
        // 注意：这里直接赋值，不需要条件判断，因为草稿恢复应该恢复所有保存的状态
        print("ClothingEditView: Restoring \(draft.imagePaths.count) images from draft")
        imagePaths = draft.imagePaths
        isShared = draft.isShared
        originalPrice = draft.originalPrice
        originalPriceJPY = draft.originalPriceJPY ?? 0
        originalPriceCurrency = ClothingPriceCurrency(rawValue: draft.originalPriceCurrencyCode ?? "") ?? .cny
        shippingFee = draft.shippingFee ?? 0
        shippingFeeJPY = draft.shippingFeeJPY ?? 0
        shippingFeeCurrency = ClothingPriceCurrency(rawValue: draft.shippingFeeCurrencyCode ?? "") ?? .cny
        syncCurrencyAmountsFromPreferredCurrency()
        priceTotal = draft.priceTotal
        deposit = draft.deposit
        balance = draft.balance
        accessoriesPrice = draft.accessoriesPrice
        stock = draft.stock
        purchaseDate = draft.purchaseDate
        depositDate = draft.depositDate
        isDepositPlan = draft.isDepositPlan
        finalPaymentDate = draft.finalPaymentDate
        finalPaymentEndDate = draft.finalPaymentEndDate
        note = draft.note
        accessoryList = draft.accessoryList
        sizeChartImagePath = draft.sizeChartImagePath
        priceChartImagePath = draft.priceChartImagePath
        draftID = draft.id

        // 恢复标签：从TagData数组中恢复Tag对象
        // 先尝试从数据库中找到对应的Tag，如果找不到则创建临时Tag对象
        restoreTags(from: draft.selectedTags)

        print("ClothingEditView: Draft restored, draftID set to \(draftID), restored \(selectedTags.count) tags")
    }

    // 从TagData恢复标签对象
    private func restoreTags(from tagDataList: [TagData]) {
        var restoredTags: [Tag] = []
        for tagData in tagDataList {
            // 尝试从数据库中查找对应的Tag
            let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == tagData.id })
            if let existingTag = try? modelContext.fetch(descriptor).first {
                // 数据库中存在该标签，使用数据库中的对象
                restoredTags.append(existingTag)
            } else {
                // 数据库中不存在，创建一个新的Tag对象（可能是标签已被删除）
                // 为了保持数据完整性，我们创建一个新的Tag
                let newTag = Tag(name: tagData.name, colorHex: tagData.colorHex)
                newTag.id = tagData.id
                modelContext.insert(newTag)
                restoredTags.append(newTag)
            }
        }
        selectedTags = restoredTags
    }

    // 重置所有状态（用于新建时清除草稿）
    private func resetAllStates() {
        print("ClothingEditView: resetAllStates called")
        name = ""
        brandName = ""
        types = ""
        colors = ""
        sizes = ""
        length = ""
        condition = "全新"
        accessories = ""
        imagePaths = []
        isShared = false
        originalPrice = 0.0
        originalPriceJPY = 0.0
        originalPriceCurrency = .cny
        originalPriceRateUpdatedAt = nil
        priceTotal = 0.0
        deposit = 0.0
        balance = 0.0
        accessoriesPrice = 0.0
        shippingFee = 0.0
        shippingFeeJPY = 0.0
        shippingFeeCurrency = .cny
        shippingRateUpdatedAt = nil
        stock = 1
        purchaseDate = Date()
        depositDate = Date()
        isDepositPlan = false
        finalPaymentDate = Date()
        finalPaymentEndDate = Date()
        note = ""
        accessoryList = []
        selectedTags = []
        sizeChartImagePath = nil
        priceChartImagePath = nil
        draftID = UUID()
        print("ClothingEditView: All states reset, new draftID: \(draftID)")
    }

    // 检查是否有有效信息（用于判断是否需要保存草稿）
    private func hasMeaningfulData() -> Bool {
        // 如果有名称、图片、品牌、类型、颜色、尺码等任何有效信息，则认为有草稿价值
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasImages = !imagePaths.isEmpty
        let hasBrand = !brandName.trimmingCharacters(in: .whitespaces).isEmpty
        let hasTypes = !types.trimmingCharacters(in: .whitespaces).isEmpty
        let hasColors = !colors.trimmingCharacters(in: .whitespaces).isEmpty
        let hasSizes = !sizes.trimmingCharacters(in: .whitespaces).isEmpty
        let hasPrice = originalPrice > 0 || originalPriceJPY > 0 || priceTotal > 0 || deposit > 0 || balance > 0 || shippingFee > 0 || shippingFeeJPY > 0
        let hasNote = !note.trimmingCharacters(in: .whitespaces).isEmpty
        let hasAccessories = !accessoryList.isEmpty
        let hasTags = !selectedTags.isEmpty
        let hasSizeChart = !(sizeChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPriceChart = !(priceChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        let result = hasName || hasImages || hasBrand || hasTypes || hasColors || hasSizes || hasPrice || hasNote || hasAccessories || hasTags || hasSizeChart || hasPriceChart
        print("ClothingEditView: hasMeaningfulData = \(result) (name: \(hasName), images: \(hasImages), brand: \(hasBrand), types: \(hasTypes), colors: \(hasColors), sizes: \(hasSizes), price: \(hasPrice), note: \(hasNote), accessories: \(hasAccessories), tags: \(hasTags), sizeChart: \(hasSizeChart), priceChart: \(hasPriceChart))")
        return result
    }

    private func normalizeTags(_ input: String) -> String {
        let components = input.replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        return components.joined(separator: ",")
    }

    private func getOrCreateBrand(name: String) -> Brand? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let descriptor = FetchDescriptor<Brand>(
            predicate: #Predicate { $0.name == trimmedName }
        )

        do {
            let brands = try modelContext.fetch(descriptor)
            if let existingBrand = brands.first {
                return existingBrand
            } else {
                let newBrand = Brand(name: trimmedName)
                modelContext.insert(newBrand)
                return newBrand
            }
        } catch {
            AppLogger.error("Failed to fetch brand: \(error)")
            // Fallback: create new
            let newBrand = Brand(name: trimmedName)
            modelContext.insert(newBrand)
            return newBrand
        }
    }

    private func updateTotalPrice() {
        // 定金和尾款都为0时，保留用户手动填的总价
        guard deposit > 0 || balance > 0 else { return }
        priceTotal = ClothingPriceHelper.shared.calculateTotal(deposit: deposit, balance: balance)
    }


    private var effectiveJPYRate: Double {
        jpyExchangeRate > 0 ? jpyExchangeRate : CurrencyExchangeRateService.defaultJPYRate
    }

    private func syncCurrencyAmountsFromPreferredCurrency() {
        let rate = effectiveJPYRate
        switch originalPriceCurrency {
        case .cny:
            originalPriceJPY = originalPrice * rate
        case .jpy:
            if originalPriceJPY == 0, originalPrice > 0 {
                originalPriceJPY = originalPrice * rate
            } else {
                originalPrice = originalPriceJPY / rate
            }
        }

        switch shippingFeeCurrency {
        case .cny:
            shippingFeeJPY = shippingFee * rate
        case .jpy:
            if shippingFeeJPY == 0, shippingFee > 0 {
                shippingFeeJPY = shippingFee * rate
            } else {
                shippingFee = shippingFeeJPY / rate
            }
        }
    }

    private func refreshJPYRateForEditor() async {
        let service = CurrencyExchangeRateService.shared
        let rate = await service.refreshJPYRateIfAllowed()
        jpyExchangeRate = rate
        originalPriceRateUpdatedAt = service.lastUpdatedAt
        shippingRateUpdatedAt = service.lastUpdatedAt
    }

    // MARK: - Toast 提示

    /// 显示提示信息
    private func showToastMessage(_ message: String, type: ToastType) {
        toastMessage = message
        toastType = type
        withAnimation(.spring(response: 0.3)) {
            showToast = true
        }
        // 2.5秒后自动隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                showToast = false
            }
        }
    }

    /// Toast 提示视图
    @ViewBuilder
    private var toastOverlay: some View {
        if showToast {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: toastType.icon)
                        .font(.title3)
                        .foregroundStyle(toastType.color)

                    Text(toastMessage)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(100)
        }
    }

    private func getAllOptions(for field: ClothingField) -> [String] {
        // Collect all unique values from existing clothings
        var options: Set<String> = []
        for item in allClothings {
            switch field {
            case .types:
                options.formUnion(item.types.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            case .colors:
                options.formUnion(item.colors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            case .sizes:
                options.formUnion(item.sizes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            case .accessories:
                options.formUnion(item.accessories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            case .length:
                if !item.length.isEmpty { options.insert(item.length) }
            case .condition:
                if !item.condition.isEmpty { options.insert(item.condition) }
            default:
                break
            }
        }
        return options.filter { !$0.isEmpty }.sorted()
    }

    private func isMultiSelect(_ field: ClothingField) -> Bool {
        switch field {
        case .types, .colors, .sizes, .accessories:
            return true
        default:
            return false
        }
    }

    private func binding(for field: ClothingField) -> Binding<String> {
        switch field {
        case .types: return $types
        case .colors: return $colors
        case .sizes: return $sizes
        case .length: return $length
        case .condition: return $condition
        case .accessories: return $accessories
        }
    }

    private func save() {
        syncCurrencyAmountsFromPreferredCurrency()
        updateTotalPrice()

        let finalBrand = getOrCreateBrand(name: brandName)
        let finalTypes = normalizeTags(types)
        let finalColors = normalizeTags(colors)
        let finalSizes = normalizeTags(sizes)
        let finalAccessories = normalizeTags(accessories)
        let finalLength = length.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let finalCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // 更新自动补全索引
        SuggestionManager.shared.addData(field: .name, value: name)
        SuggestionManager.shared.addData(field: .brand, value: brandName)
        SuggestionManager.shared.addData(field: .type, value: finalTypes)
        SuggestionManager.shared.addData(field: .color, value: finalColors)
        SuggestionManager.shared.addData(field: .size, value: finalSizes)
        SuggestionManager.shared.addData(field: .accessory, value: finalAccessories)
        SuggestionManager.shared.addData(field: .condition, value: finalCondition)

        // 特殊逻辑：如果类型包含"小物"，则该物品名称也加入小物索引
        SuggestionManager.shared.addAccessoryNameIfTypeContainsAccessory(name: name, types: finalTypes)
        var notificationTarget: Clothing?

        if let c = clothing {
            // Update
            AppLogger.info("Updating clothing: \(c.id)")
            let wasDepositPlan = c.isDepositPlan
            let oldSizeChartPath = c.sizeChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let oldPriceChartPath = c.priceChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            c.name = name
            c.brand = finalBrand
            c.types = finalTypes
            c.colors = finalColors
            c.sizes = finalSizes
            c.length = finalLength
            c.condition = finalCondition
            c.accessories = finalAccessories
            // 检查 replacedCutoutID 是否还有效
            if let replacedID = c.replacedCutoutID {
                // 如果图片列表为空，或者 replacedCutoutID 对应的图片已经不在 imagePaths 中，则重置
                // 注意：imagePaths 存储的是文件名，我们需要根据 replacedCutoutID 找到对应的 CutoutItem，然后获取其 imagePath

                // 为了性能，我们先不查数据库，而是直接在 CutoutService 中提供一个辅助检查方法
                // 或者更简单：我们不依赖 CutoutItem 的查找，而是依赖 CutoutService.handleCutoutDeletion 已经在删除时处理了。
                // 但是！这里是全量替换 imagePaths。如果是 UI 上的“删除”操作，已经在 ImagePickerGrid 中触发了 handleCutoutDeletion。
                // 如果是“移动”或“添加”操作，imagePaths 会变化，但文件没被删。

                // 用户的需求是：若图片里删除抠图，则保存时，clothing.replacedCutoutID, 也应该重新保存（置空或更新）。
                // 在 ClothingEditView 中，imagePaths 是最终状态。
                // 如果 replacedCutoutID 对应的抠图图片还在 imagePaths 中，则保留。
                // 如果不在了，则置空。

                // 问题：我们只知道 replacedCutoutID (UUID)，不知道它对应的 imagePath。
                // 所以必须查询 CutoutItem。

                let descriptor = FetchDescriptor<CutoutItem>(predicate: #Predicate { $0.id == replacedID })
                if let cutout = try? modelContext.fetch(descriptor).first {
                    if !imagePaths.contains(cutout.imagePath) {
                        c.replacedCutoutID = nil
                    }
                } else {
                    // 找不到 CutoutItem，说明可能被删了，或者数据不一致
                    c.replacedCutoutID = nil
                }
            }

            c.imagePaths = imagePaths
            c.isShared = isShared
            c.originalPrice = Decimal(originalPrice)
            c.originalPriceJPY = Decimal(originalPriceJPY)
            c.originalPriceCurrencyCode = originalPriceCurrency.rawValue
            c.originalPriceExchangeRateJPY = Decimal(effectiveJPYRate)
            c.originalPriceRateUpdatedAt = originalPriceRateUpdatedAt
            c.shippingFee = Decimal(shippingFee)
            c.shippingFeeJPY = Decimal(shippingFeeJPY)
            c.shippingFeeCurrencyCode = shippingFeeCurrency.rawValue
            c.shippingExchangeRateJPY = Decimal(effectiveJPYRate)
            c.shippingRateUpdatedAt = shippingRateUpdatedAt
            c.price = Decimal(priceTotal)
            c.deposit = Decimal(deposit)
            c.balance = Decimal(balance)
            c.accessoriesPrice = Decimal(accessoriesPrice)

            // Update accessory items
            // Remove old items (since we are replacing the list)
            if let oldItems = c.accessoryItems {
                for item in oldItems {
                    modelContext.delete(item)
                }
            }
            // Create new items
            let newItems = accessoryList.enumerated().map { index, data in
                AccessoryItem(
                    name: data.name,
                    price: Decimal(data.price),
                    deposit: Decimal(data.deposit),
                    balance: Decimal(data.balance),
                    sortIndex: index,
                    imagePaths: data.imagePaths
                )
            }
            c.accessoryItems = newItems

            c.purchaseDate = purchaseDate
            c.depositDate = depositDate
            c.isDepositPlan = isDepositPlan
            c.finalPaymentDate = finalPaymentDate
            c.finalPaymentEndDate = finalPaymentEndDate
            if wasDepositPlan && !isDepositPlan {
                try? WealthSavingLedger.markActiveSavingsUsed(for: c.id, context: modelContext)
            }
            if !isDepositPlan {
                c.isFinalPaymentSavedToWealth = false
                c.finalPaymentSavedAt = nil
            }
            c.note = note
            c.stock = stock
            c.tags = selectedTags
            let now = Date()
            c.updatedAt = now
            c.lastModified = now

            // 保存表图字段
            let newSizeChartPath = sizeChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let newPriceChartPath = priceChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            c.sizeChartImagePath = (newSizeChartPath?.isEmpty == true) ? nil : newSizeChartPath
            c.priceChartImagePath = (newPriceChartPath?.isEmpty == true) ? nil : newPriceChartPath

            if let oldSizeChartPath, !oldSizeChartPath.isEmpty, oldSizeChartPath != c.sizeChartImagePath {
                ImageManager.shared.deleteImage(fileName: oldSizeChartPath, context: modelContext)
            }
            if let oldPriceChartPath, !oldPriceChartPath.isEmpty, oldPriceChartPath != c.priceChartImagePath {
                ImageManager.shared.deleteImage(fileName: oldPriceChartPath, context: modelContext)
            }
            notificationTarget = c
        } else {
            // Create
            AppLogger.info("Creating new clothing: \(name)")
            let newClothing = Clothing(
                name: name,
                brand: finalBrand,
                types: finalTypes,
                colors: finalColors,
                sizes: finalSizes,
                length: finalLength,
                condition: finalCondition,
                accessories: finalAccessories,
                imagePaths: imagePaths,
                isShared: isShared,
                originalPrice: Decimal(originalPrice),
                originalPriceJPY: Decimal(originalPriceJPY),
                originalPriceCurrencyCode: originalPriceCurrency.rawValue,
                originalPriceExchangeRateJPY: Decimal(effectiveJPYRate),
                originalPriceRateUpdatedAt: originalPriceRateUpdatedAt,
                price: Decimal(priceTotal),
                deposit: Decimal(deposit),
                balance: Decimal(balance),
                accessoriesPrice: Decimal(accessoriesPrice),
                shippingFee: Decimal(shippingFee),
                shippingFeeJPY: Decimal(shippingFeeJPY),
                shippingFeeCurrencyCode: shippingFeeCurrency.rawValue,
                shippingExchangeRateJPY: Decimal(effectiveJPYRate),
                shippingRateUpdatedAt: shippingRateUpdatedAt,
                purchaseDate: purchaseDate,
                depositDate: depositDate,
                isDepositPlan: isDepositPlan,
                finalPaymentDate: finalPaymentDate,
                finalPaymentEndDate: finalPaymentEndDate,
                note: note,
                stock: stock
            )

            // 保存表图字段
            let newSizeChartPath = sizeChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let newPriceChartPath = priceChartImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            newClothing.sizeChartImagePath = (newSizeChartPath?.isEmpty == true) ? nil : newSizeChartPath
            newClothing.priceChartImagePath = (newPriceChartPath?.isEmpty == true) ? nil : newPriceChartPath

            let newItems = accessoryList.enumerated().map { index, data in
                AccessoryItem(
                    name: data.name,
                    price: Decimal(data.price),
                    deposit: Decimal(data.deposit),
                    balance: Decimal(data.balance),
                    sortIndex: index,
                    imagePaths: data.imagePaths
                )
            }
            newClothing.accessoryItems = newItems

            newClothing.tags = selectedTags
            let now = Date()
            newClothing.updatedAt = now
            newClothing.lastModified = now
            modelContext.insert(newClothing)
            notificationTarget = newClothing

            // Trigger Reward for adding new clothing
            RewardManager.shared.triggerReward(type: .addClothing)
        }

        // Save context and sync widget
        do {
            try modelContext.save()
            if let notificationTarget {
                NotificationManager.shared.scheduleNotification(for: notificationTarget, modelContext: modelContext)
            }
            Task { await SharedPersistence.shared.syncWidgetData(reason: "clothing-edit-save") }

            // 更新衣物数量缓存，用于魔法任务进度实时显示
            updateClothingCountCache()
        } catch {
            AppLogger.error("Failed to save context: \(error)")
        }

        dismiss()
    }

    /// 更新衣物数量缓存，用于魔法任务进度实时显示
    private func updateClothingCountCache() {
        FeatureUnlockManager.shared.refreshClothingCountCache(from: modelContext, reason: "clothing-edit-save")
    }
}
