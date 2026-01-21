
import SwiftUI

struct OOTDPreviewView: View {
    let outfit: Outfit
    
    var body: some View {
        ZStack {
            Color.white
            ForEach(outfit.items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                if let cutout = item.cutout, 
                   let uiImage = ImageManager.shared.loadImage(fileName: cutout.imagePath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .scaleEffect(item.scale)
                        .rotationEffect(Angle(degrees: item.rotation))
                        .offset(x: item.x, y: item.y)
                }
            }
        }
        .frame(width: 300, height: 300) // Standard size for thumbnail generation
    }
}
