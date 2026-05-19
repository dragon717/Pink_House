import SwiftUI

struct PathNode: Identifiable, Codable, Equatable {
    var id = UUID()
    var x: CGFloat
    var y: CGFloat
}

struct PetPath: Identifiable, Codable {
    var id = UUID()
    var name: String
    var roomIndex: Int // 0 for room1, 1 for room2
    var nodes: [PathNode]
    var duration: TimeInterval = 10.0
}

struct SmallWorldPetConfig {
    var paths: [PetPath] = []
    
    init() {
        self.paths = Self.createDefaultPaths()
    }
    
    static func createDefaultPaths() -> [PetPath] {
        // Path 1 in the first House room preset.
        let path1 = PetPath(name: "Room 1 Path", roomIndex: 0, nodes: [
            PathNode(x: 0.193, y: 0.495),
            PathNode(x: 0.308, y: 0.657),
            PathNode(x: 0.380, y: 0.737),
            PathNode(x: 0.590, y: 0.564),
            PathNode(x: 0.772, y: 0.744),
        ], duration: 12.0)
        
        // Path 2 in the second House room preset.
        let path2 = PetPath(name: "Room 2 Path", roomIndex: 1, nodes: [
            PathNode(x: 0.676, y: 0.839),
            PathNode(x: 0.603, y: 0.721),
            PathNode(x: 0.405, y: 0.618),
            PathNode(x: 0.507, y: 0.480),
            PathNode(x: 0.754, y: 0.285),
        ], duration: 12.0)
        
        return [path1, path2]
    }
    
    mutating func updateNode(pathId: UUID, nodeId: UUID, newX: CGFloat, newY: CGFloat) {
        if let pathIndex = paths.firstIndex(where: { $0.id == pathId }),
           let nodeIndex = paths[pathIndex].nodes.firstIndex(where: { $0.id == nodeId }) {
            paths[pathIndex].nodes[nodeIndex].x = newX
            paths[pathIndex].nodes[nodeIndex].y = newY
        }
    }
}
