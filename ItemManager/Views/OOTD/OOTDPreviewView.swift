
import SwiftUI

struct OOTDPreviewView: View {
    let outfit: Outfit
    
    // Standard Reference Size (Same as Canvas)
    private let canvasWidth: CGFloat = 1080
    private let canvasHeight: CGFloat = 1440
    
    var body: some View {
        ZStack {
            if outfit.canvasType == "blank" {
                Color.white
                    .frame(width: canvasWidth, height: canvasHeight)
            } else {
                Image("ootd_background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasWidth, height: canvasHeight)
                    .clipped()
            }
            
            ForEach(outfit.items.sorted(by: { $0.zIndex < $1.zIndex })) { item in
                if let cutout = item.cutout, 
                   let uiImage = ImageManager.shared.loadImage(fileName: cutout.imagePath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        // 200 is base size in CanvasItemView
                        .frame(width: 200, height: 200) 
                        .scaleEffect(item.scale)
                        .rotationEffect(Angle(degrees: item.rotation))
                        .offset(x: item.x, y: item.y)
                }
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
    }
}
