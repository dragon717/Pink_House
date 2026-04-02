import SwiftUI

struct SmallWorldPetOverlay: View {
    @ObservedObject var viewModel: SmallWorldPetViewModel
    let roomIndex: Int
    var geometry: GeometryProxy? = nil
    var containerSize: CGSize? = nil
    
    // 获取实际使用的尺寸
    private var size: CGSize {
        containerSize ?? geometry?.size ?? CGSize(width: 100, height: 100)
    }
    
    var body: some View {
        ZStack {
            // Debug Layer (Bottom to not block clicks if needed, but gestures are on top usually)
            // Wait, we want to see path under the pet?
            
            if viewModel.isDebugMode {
                debugView
            }
            
            // Pet Layer
            if let activePathId = viewModel.activePathId,
               let path = viewModel.config.paths.first(where: { $0.id == activePathId }),
               path.roomIndex == roomIndex,
               viewModel.isVisible {
                
                petView
                    .position(
                        x: viewModel.currentPosition.x * size.width,
                        y: viewModel.currentPosition.y * size.height
                    )
            }
        }
    }
    
    @ViewBuilder
    var petView: some View {
        SeamlessVideoPlayer(
            videoName: viewModel.currentMotionVideoName,
            isLooping: viewModel.isMotionVideoLooping,
            isMirrored: viewModel.isMotionVideoMirrored,
            playbackRate: viewModel.motionPlaybackRate,
            isMuted: true,
            volume: 0,
            onFinished: {
                viewModel.handleMotionVideoFinished()
            }
        )
        .frame(width: 40, height: 40) // Adjust size as needed
        .shadow(radius: 5)
    }
    
    var debugView: some View {
        ZStack {
            // Debug border to show overlay area
            Rectangle()
                .stroke(Color.red, lineWidth: 2)
                .opacity(0.3)
            
            // Show paths for this room
            ForEach(viewModel.config.paths.filter { $0.roomIndex == roomIndex }) { path in
                ZStack {
                    PathShape(nodes: path.nodes, size: size)
                        .stroke(path.id == viewModel.selectedPathId ? Color.red : Color.blue.opacity(0.8), style: StrokeStyle(lineWidth: 3, dash: [5]))
                    
                    ForEach(path.nodes) { node in
                        Circle()
                            .fill(path.id == viewModel.selectedPathId ? Color.green : Color.yellow)
                            .frame(width: 16, height: 16)
                            .position(
                                x: node.x * size.width,
                                y: node.y * size.height
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        viewModel.selectedPathId = path.id
                                        // Calculate new normalized position
                                        let newX = min(max(value.location.x / size.width, 0), 1)
                                        let newY = min(max(value.location.y / size.height, 0), 1)
                                        viewModel.updateNodePosition(nodeId: node.id, x: newX, y: newY)
                                    }
                            )
                            .onTapGesture {
                                viewModel.selectedPathId = path.id
                            }
                    }
                    
                    // Play button at start
                    if let start = path.nodes.first {
                        Button(action: {
                            viewModel.startMovement(pathId: path.id)
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.green)
                                .background(Circle().fill(Color.white))
                        }
                        .position(
                            x: start.x * size.width,
                            y: (start.y - 0.08) * size.height
                        )
                    }
                }
            }
        }
    }
}

struct PathShape: Shape {
    let nodes: [PathNode]
    var geometry: GeometryProxy? = nil
    var size: CGSize? = nil
    
    // 获取实际使用的尺寸
    private var effectiveSize: CGSize {
        size ?? geometry?.size ?? CGSize(width: 100, height: 100)
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = nodes.first else { return path }
        
        let effectiveSize = self.effectiveSize
        let p0 = CGPoint(x: first.x * effectiveSize.width, y: first.y * effectiveSize.height)
        path.move(to: p0)
        
        for i in 1..<nodes.count {
            let node = nodes[i]
            let p = CGPoint(x: node.x * effectiveSize.width, y: node.y * effectiveSize.height)
            path.addLine(to: p)
        }
        
        return path
    }
}
