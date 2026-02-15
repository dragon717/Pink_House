import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ReorderableDropDelegate: DropDelegate {
    let item: Outfit
    var pages: [Outfit]
    var onMove: (Outfit, Outfit) -> Void
    
    func dropEntered(info: DropInfo) {
        guard info.hasItemsConforming(to: [.text]) else { return }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.text])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        if let itemProvider = info.itemProviders(for: [.text]).first {
            itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
                if let data = data as? Data, let idString = String(data: data, encoding: .utf8), let uuid = UUID(uuidString: idString) {
                    DispatchQueue.main.async {
                        if let source = pages.first(where: { $0.id == uuid }) {
                            onMove(source, item)
                        }
                    }
                }
            }
            return true
        }
        return false
    }
}
