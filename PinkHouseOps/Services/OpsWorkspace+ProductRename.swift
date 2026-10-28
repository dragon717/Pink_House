import Foundation
import SharedCatalog

extension OpsWorkspace {
    /// 采用两端同一份计划；尺码表、规格、价格和图片依然按原商品 ID 关联。
    func applyProductRenamePlan(_ plan: ShopCatalogProductRename.Plan) {
        let replacements = Dictionary(uniqueKeysWithValues: plan.products.map { ($0.id, $0) })
        for index in catalog.products.indices {
            if let product = replacements[catalog.products[index].id] {
                catalog.products[index] = product
            }
        }
        let profileIDs = Set(plan.styleProfile.removals + plan.styleProfile.upserts.map(\.id))
        catalog.styleProfiles.removeAll { profileIDs.contains($0.id) }
        catalog.styleProfiles.append(contentsOf: plan.styleProfile.upserts)
    }

    func productRenamePreview(productID: String, name: String, category: String) -> String? {
        guard let product = catalog.products.first(where: { $0.id == productID }),
              name.trimmingCharacters(in: .whitespacesAndNewlines) != product.name
                || category.trimmingCharacters(in: .whitespacesAndNewlines) != product.category else { return nil }
        let plan = ShopCatalogProductRename.plan(product: product, newName: name, newCategory: category,
            among: catalog.products, profiles: catalog.styleProfiles)
        return "款式名：\(plan.designNameAfter)；本款共 \(plan.products.count) 条商品一起更新。"
            + "图片、价格和尺码表保留。已加入衣橱的记录保留原名称。"
    }

    /// 两个命名表单均走此保存事务。落盘失败回滚目录，表单里的新名称可继续重试。
    @discardableResult
    func saveProductIdentity(id: String, shopID: String, seriesID: String,
                             name: String, category: String) -> Bool {
        saveProductEdit {
            updateProduct(id: id, shopID: shopID, seriesID: seriesID, name: name, category: category)
        }
    }

    @discardableResult
    func saveProductEdit(_ edit: () -> Bool) -> Bool {
        guard canMutate(), let draft else { return false }
        let previous = catalog
        let revision = draft.draftRevision
        let reviewedRevision = draft.reviewedRevision
        guard edit() else { return false }
        guard saveCatalogEditorChanges() else {
            catalog = previous
            draft.draftRevision = revision
            draft.reviewedRevision = reviewedRevision
            return false
        }
        return true
    }
}
