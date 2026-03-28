import SwiftUI
import UIKit

// MARK: - Pattern Background
struct PatternBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 60
            let rows = Int(size.height / spacing) + 1
            let cols = Int(size.width / spacing) + 1
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * spacing + (row % 2 == 0 ? 0 : spacing/2)
                    let y = CGFloat(row) * spacing
                    
                    // Simple deterministic pseudo-random choice based on position
                    let choice = (row + col) % 3 == 0 ? "pawprint.fill" : "leaf"
                    let rotation = Angle.degrees(Double((row * col * 13) % 60 - 30))
                    
                    if let symbol = context.resolveSymbol(id: choice) {
                        context.drawLayer { ctx in
                            ctx.translateBy(x: x, y: y)
                            ctx.rotate(by: rotation)
                            ctx.draw(symbol, at: .zero)
                        }
                    }
                }
            }
        } symbols: {
            Image(systemName: "leaf")
                .font(.system(size: 14))
                .tag("leaf")
            Image(systemName: "pawprint.fill")
                .font(.system(size: 14))
                .tag("pawprint.fill")
        }
        .foregroundStyle(Color(hex: "FFB6C1").opacity(0.15))
    }
}

// MARK: - Stamp View
struct StampView: View {
    var body: some View {
        ZStack {
            // 外圈圆环
            Circle()
                .stroke(Color(hex: "FF69B4").opacity(0.6), lineWidth: 3)
                .frame(width: 60, height: 60)
            
            // 内部双圆环装饰
            Circle()
                .stroke(Color(hex: "FF69B4").opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .frame(width: 52, height: 52)
            
            // 猫爪 (镂空效果通过混合模式或直接用前景色)
            // 这里我们用一种“印章”风格：半透明填充
            Image(systemName: "pawprint.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color(hex: "FF69B4").opacity(0.5))
                .rotationEffect(.degrees(10))
            
            // 文字装饰
            Text("REVIEWED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "FF69B4"))
                .offset(y: 22)
                .rotationEffect(.degrees(-10))
        }
        .compositingGroup() // 组合后应用混合模式（如果需要更复杂的镂空）
        .opacity(0.8)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    var isAI: Bool = false
    var onImageTap: ((UIImage) -> Void)? = nil
    var onReport: (() -> Void)? = nil
    
    @State private var showingReportButton = false

    private var currentPetCharacter: PetCharacter {
        guard let petId = PetDataManager.shared.status.selectedPetId,
              let character = PetCharacter(rawValue: petId) else {
            return .naicha
        }
        return character
    }

    private var defaultPetExpressionImageName: String {
        if UIImage(named: currentPetCharacter.quickOptionIconName) != nil {
            return currentPetCharacter.quickOptionIconName
        }
        return currentPetCharacter.happyImageName
    }

    private func fallbackEmotionImageName(for imageName: String) -> String? {
        if imageName.hasSuffix("_cat") || imageName == "cat" {
            return UIImage(named: "cat") != nil ? "cat" : "happy_cat"
        }
        if imageName.hasSuffix("_dog") || imageName == "dog" {
            return UIImage(named: "dog") != nil ? "dog" : "happy_dog"
        }
        return defaultPetExpressionImageName
    }

    private func resolvedBubbleImageName(from rawName: String) -> String {
        if UIImage(named: rawName) != nil {
            return rawName
        }
        if let fallback = fallbackEmotionImageName(for: rawName), UIImage(named: fallback) != nil {
            return fallback
        }
        return rawName
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    // User Image (from analysis)
                    if let imagePath = message.imagePath {
                        // 优化：使用 AsyncImage 异步加载本地图片，避免阻塞主线程
                        AsyncImage(url: getFileURL(fileName: imagePath)) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 100, height: 100)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 200)
                                    .cornerRadius(12)
                                    .padding(4)
                                    .background(Color.white)
                                    .cornerRadius(16)
                                    .shadow(color: .pink.opacity(0.1), radius: 4, x: 0, y: 2)
                                    .onTapGesture {
                                        // 这里 AsyncImage 返回的是 Image，但回调需要 UIImage
                                        // 这是一个限制，所以如果需要全屏查看，我们可能需要额外处理
                                        // 简单方案：再次同步加载 UIImage 传给回调 (虽然有点浪费，但全屏查看频率低)
                                        if let uiImage = loadImageFromDisk(fileName: imagePath) {
                                            onImageTap?(uiImage)
                                        }
                                    }
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundStyle(.gray)
                                    .frame(width: 100, height: 100)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    
                    Text(PetGenerativePromptBuilder.sanitizeMessageText(message.text))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "FFB6C1"), Color(hex: "FF69B4")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .corners([.topLeft, .topRight, .bottomLeft], radius: 20)
                        .corners([.bottomRight], radius: 4)
                        .shadow(color: .pink.opacity(0.2), radius: 4, x: 0, y: 2)
                    
                    Text(formatTimestamp(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.gray.opacity(0.8))
                        .padding(.trailing, 4)
                }
            } else {
                // AI 回复
                VStack(alignment: .leading, spacing: 4) {
                    // AI 生成标识
                    if isAI {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                            Text("AI 生成")
                                .font(.caption2)
                        }
                        .foregroundStyle(.pink.opacity(0.8))
                        .padding(.leading, 4)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // 1. 图片内容 (如果有)
                        if let imageName = message.imageName {
                            let resolvedImageName = resolvedBubbleImageName(from: imageName)
                            // 尝试加载图片，如果 Assets 中没有，显示占位符
                            if let image = UIImage(named: resolvedImageName) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 200)
                                    .cornerRadius(12)
                                    .overlay(alignment: .bottomTrailing) {
                                        StampView()
                                            .scaleEffect(0.5)
                                            .padding(4)
                                    }
                                    .onTapGesture {
                                        onImageTap?(image)
                                    }
                            } else {
                                // 调试用占位符
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.1))
                                        .frame(width: 150, height: 150)
                                        .cornerRadius(12)
                                    
                                    VStack {
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundColor(.gray)
                                        Text(imageName)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                        
                        // 2. 文字内容
                        Text(PetGenerativePromptBuilder.sanitizeMessageText(message.text))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                ZStack {
                                    Color(hex: "FFF0F5")
                                    PatternBackground()
                                        .opacity(0.3)
                                }
                            )
                            .foregroundColor(Color(hex: "4A4A4A"))
                            .cornerRadius(20)
                            .corners([.topLeft, .topRight, .bottomRight], radius: 20)
                            .corners([.bottomLeft], radius: 4)
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            .onLongPressGesture {
                                if isAI {
                                    showingReportButton = true
                                }
                            }
                    }
                    
                    HStack(spacing: 12) {
                        Text(formatTimestamp(message.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.gray.opacity(0.8))
                        
                        // 举报按钮 (长按后显示)
                        if isAI && showingReportButton {
                            Button(action: {
                                onReport?()
                                showingReportButton = false
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "exclamationmark.bubble")
                                        .font(.caption2)
                                    Text("举报")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.pink)
                            }
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .padding(.leading, 4)
                }
                
                Spacer()
            }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func loadImageFromDisk(fileName: String) -> UIImage? {
        let fileURL = getFileURL(fileName: fileName)
        return UIImage(contentsOfFile: fileURL.path)
    }
    
    private func getFileURL(fileName: String) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }
}

// MARK: - Image Viewing Helpers
struct ImageWrapper: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct FullScreenImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
            
            // Close button area
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onTapGesture {
            dismiss()
        }
    }
}

// MARK: - Extensions
extension View {
    func corners(_ corners: UIRectCorner, radius: CGFloat) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}
