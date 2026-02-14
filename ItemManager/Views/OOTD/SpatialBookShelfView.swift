import SwiftUI
import SceneKit

struct SpatialBookShelfView: View {
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Title
                Text("空间手帐")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                // 3D Fitting / Spatial Outfit Entry
                NavigationLink(destination: ThreeDOOTDView()) {
                    HStack {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 24))
                        Text("空间穿搭 (3D试衣)")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                }
                .padding(.horizontal, 40)
                
                // Placeholder for 3D Books
                VStack {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)
                    Text("立体手帐本 (开发中)")
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
    }
}
