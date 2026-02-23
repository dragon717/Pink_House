import Foundation
import SwiftData

/// 删除追踪器
/// 用于记录删除操作，在应用启动时应用这些删除，避免iCloud同步覆盖
@MainActor
final class DeleteTracker {
    static let shared = DeleteTracker()
    
    private let userDefaults = UserDefaults.standard
    private let deletedOutfitsKey = "deletedOutfits"
    private let deletedClothingsKey = "deletedClothings"
    private let deletedBookGroupsKey = "deletedBookGroups"
    private let deletedModel3DsKey = "deletedModel3Ds"
    private let deletedPerlerPatternsKey = "deletedPerlerPatterns"
    
    // MARK: - 记录删除
    
    func recordDeletedOutfit(id: UUID) {
        var deletedIDs = getDeletedOutfitIDs()
        deletedIDs.append(id)
        userDefaults.set(deletedIDs.map { $0.uuidString }, forKey: deletedOutfitsKey)
        print("DeleteTracker: Recorded deleted outfit \(id)")
    }
    
    func recordDeletedClothing(id: UUID) {
        var deletedIDs = getDeletedClothingIDs()
        deletedIDs.append(id)
        userDefaults.set(deletedIDs.map { $0.uuidString }, forKey: deletedClothingsKey)
        print("DeleteTracker: Recorded deleted clothing \(id)")
    }
    
    func recordDeletedBookGroup(id: UUID) {
        var deletedIDs = getDeletedBookGroupIDs()
        deletedIDs.append(id)
        userDefaults.set(deletedIDs.map { $0.uuidString }, forKey: deletedBookGroupsKey)
        print("DeleteTracker: Recorded deleted book group \(id)")
    }

    func recordDeletedModel3D(id: UUID) {
        var deletedIDs = getDeletedModel3DIDs()
        deletedIDs.append(id)
        userDefaults.set(deletedIDs.map { $0.uuidString }, forKey: deletedModel3DsKey)
        print("DeleteTracker: Recorded deleted 3D model \(id)")
    }

    func recordDeletedPerlerPattern(id: UUID) {
        var deletedIDs = getDeletedPerlerPatternIDs()
        deletedIDs.append(id)
        userDefaults.set(deletedIDs.map { $0.uuidString }, forKey: deletedPerlerPatternsKey)
        print("DeleteTracker: Recorded deleted perler pattern \(id)")
    }

    // MARK: - 获取记录的删除
    
    func getDeletedOutfitIDs() -> [UUID] {
        guard let strings = userDefaults.stringArray(forKey: deletedOutfitsKey) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }
    
    func getDeletedClothingIDs() -> [UUID] {
        guard let strings = userDefaults.stringArray(forKey: deletedClothingsKey) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }
    
    func getDeletedBookGroupIDs() -> [UUID] {
        guard let strings = userDefaults.stringArray(forKey: deletedBookGroupsKey) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    func getDeletedModel3DIDs() -> [UUID] {
        guard let strings = userDefaults.stringArray(forKey: deletedModel3DsKey) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    func getDeletedPerlerPatternIDs() -> [UUID] {
        guard let strings = userDefaults.stringArray(forKey: deletedPerlerPatternsKey) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    // MARK: - 应用删除
    
    func applyDeletedOutfits(context: ModelContext) {
        let deletedIDs = getDeletedOutfitIDs()
        guard !deletedIDs.isEmpty else { return }
        
        print("DeleteTracker: Applying \(deletedIDs.count) deleted outfits")
        
        let descriptor = FetchDescriptor<Outfit>()
        do {
            let allOutfits = try context.fetch(descriptor)
            var appliedCount = 0
            
            for outfit in allOutfits {
                if deletedIDs.contains(outfit.id) && !outfit.isDeleted {
                    outfit.isDeleted = true
                    outfit.deletedAt = Date()
                    outfit.lastModified = Date()
                    appliedCount += 1
                    print("DeleteTracker: Applied delete to outfit '\(outfit.note)' (ID: \(outfit.id))")
                }
            }
            
            if appliedCount > 0 {
                try context.save()
                print("DeleteTracker: Applied \(appliedCount) outfit deletes")
            }
            
            // 清理已应用的删除记录
            clearDeletedOutfits()
        } catch {
            print("DeleteTracker: Failed to apply outfit deletes: \(error)")
        }
    }
    
    func applyDeletedClothings(context: ModelContext) {
        let deletedIDs = getDeletedClothingIDs()
        guard !deletedIDs.isEmpty else { return }
        
        print("DeleteTracker: Applying \(deletedIDs.count) deleted clothings")
        
        let descriptor = FetchDescriptor<Clothing>()
        do {
            let allClothings = try context.fetch(descriptor)
            var appliedCount = 0
            
            for clothing in allClothings {
                if deletedIDs.contains(clothing.id) && !clothing.isDeleted {
                    clothing.isDeleted = true
                    clothing.deletedAt = Date()
                    clothing.lastModified = Date()
                    appliedCount += 1
                    print("DeleteTracker: Applied delete to clothing '\(clothing.name)' (ID: \(clothing.id))")
                }
            }
            
            if appliedCount > 0 {
                try context.save()
                print("DeleteTracker: Applied \(appliedCount) clothing deletes")
            }
            
            clearDeletedClothings()
        } catch {
            print("DeleteTracker: Failed to apply clothing deletes: \(error)")
        }
    }
    
    func applyDeletedBookGroups(context: ModelContext) {
        let deletedIDs = getDeletedBookGroupIDs()
        guard !deletedIDs.isEmpty else { return }
        
        print("DeleteTracker: Applying \(deletedIDs.count) deleted book groups")
        
        let descriptor = FetchDescriptor<BookGroup>()
        do {
            let allBookGroups = try context.fetch(descriptor)
            var appliedCount = 0
            
            for bookGroup in allBookGroups {
                if deletedIDs.contains(bookGroup.id) && !bookGroup.isDeleted {
                    bookGroup.isDeleted = true
                    bookGroup.deletedAt = Date()
                    bookGroup.lastModified = Date()
                    appliedCount += 1
                    print("DeleteTracker: Applied delete to book group '\(bookGroup.title)' (ID: \(bookGroup.id))")
                }
            }
            
            if appliedCount > 0 {
                try context.save()
                print("DeleteTracker: Applied \(appliedCount) book group deletes")
            }
            
            clearDeletedBookGroups()
        } catch {
            print("DeleteTracker: Failed to apply book group deletes: \(error)")
        }
    }

    func applyDeletedModel3Ds(context: ModelContext) {
        let deletedIDs = getDeletedModel3DIDs()
        guard !deletedIDs.isEmpty else { return }

        print("DeleteTracker: Applying \(deletedIDs.count) deleted 3D models")

        let descriptor = FetchDescriptor<Model3D>()
        do {
            let allModel3Ds = try context.fetch(descriptor)
            var appliedCount = 0

            for model3D in allModel3Ds {
                if deletedIDs.contains(model3D.id) && !model3D.isDeleted {
                    model3D.isDeleted = true
                    model3D.deletedAt = Date()
                    model3D.lastModified = Date()
                    appliedCount += 1
                    print("DeleteTracker: Applied delete to 3D model '\(model3D.name)' (ID: \(model3D.id))")
                }
            }

            if appliedCount > 0 {
                try context.save()
                print("DeleteTracker: Applied \(appliedCount) 3D model deletes")
            }

            clearDeletedModel3Ds()
        } catch {
            print("DeleteTracker: Failed to apply 3D model deletes: \(error)")
        }
    }

    func applyDeletedPerlerPatterns(context: ModelContext) {
        let deletedIDs = getDeletedPerlerPatternIDs()
        guard !deletedIDs.isEmpty else { return }

        print("DeleteTracker: Applying \(deletedIDs.count) deleted perler patterns")

        let descriptor = FetchDescriptor<PerlerBeadPattern>()
        do {
            let allPatterns = try context.fetch(descriptor)
            var appliedCount = 0

            for pattern in allPatterns {
                if deletedIDs.contains(pattern.id) && !pattern.isDeleted {
                    pattern.isDeleted = true
                    pattern.deletedAt = Date()
                    pattern.lastModified = Date()
                    appliedCount += 1
                    print("DeleteTracker: Applied delete to perler pattern '\(pattern.name)' (ID: \(pattern.id))")
                }
            }

            if appliedCount > 0 {
                try context.save()
                print("DeleteTracker: Applied \(appliedCount) perler pattern deletes")
            }

            clearDeletedPerlerPatterns()
        } catch {
            print("DeleteTracker: Failed to apply perler pattern deletes: \(error)")
        }
    }

    // MARK: - 清理记录

    func clearDeletedOutfits() {
        userDefaults.removeObject(forKey: deletedOutfitsKey)
        print("DeleteTracker: Cleared outfit delete records")
    }

    func clearDeletedClothings() {
        userDefaults.removeObject(forKey: deletedClothingsKey)
        print("DeleteTracker: Cleared clothing delete records")
    }

    func clearDeletedBookGroups() {
        userDefaults.removeObject(forKey: deletedBookGroupsKey)
        print("DeleteTracker: Cleared book group delete records")
    }

    func clearDeletedModel3Ds() {
        userDefaults.removeObject(forKey: deletedModel3DsKey)
        print("DeleteTracker: Cleared 3D model delete records")
    }

    func clearDeletedPerlerPatterns() {
        userDefaults.removeObject(forKey: deletedPerlerPatternsKey)
        print("DeleteTracker: Cleared perler pattern delete records")
    }

    // MARK: - 应用所有删除

    func applyAllDeletes(context: ModelContext) {
        print("DeleteTracker: Applying all tracked deletes...")
        applyDeletedOutfits(context: context)
        applyDeletedClothings(context: context)
        applyDeletedModel3Ds(context: context)
        applyDeletedBookGroups(context: context)
        applyDeletedPerlerPatterns(context: context)
        print("DeleteTracker: Finished applying deletes")
    }
}
