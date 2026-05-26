import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ReorderableDropDelegate: DropDelegate {
    let item: Outfit
    @Binding var draggingItem: Outfit?
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
        guard let source = draggingItem else {
            return false
        }

        DispatchQueue.main.async {
            onMove(source, item)
            draggingItem = nil
        }
        return true
    }
}
