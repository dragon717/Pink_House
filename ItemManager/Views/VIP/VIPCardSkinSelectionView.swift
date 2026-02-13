import SwiftUI

struct VIPCardSkinSelectionView: View {
    @ObservedObject var vipManager = VIPManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
            if vipManager.cardStyle == .blackGold {
                Color(hex: "121212")
                    .ignoresSafeArea()
            } else {
                // Use App Background Image or Color
                Group {
                    if themeManager.backgroundStyle == .image, let image = themeManager.backgroundImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                    } else {
                        themeManager.backgroundColor
                            .ignoresSafeArea()
                    }
                }
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 30) {
                Text("选择卡片皮肤")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 32) {
                        ForEach(VIPCardStyle.allCases) { style in
                            VStack(spacing: 16) {
                                VIPCardView(
                                    vipNumber: vipManager.vipNumber ?? "88888888",
                                    expireDate: vipManager.vipExpireDate ?? Date(),
                                    isVIP: true,
                                    cardStyle: style
                                )
                                .frame(width: geometry.size.width - 64, height: 220)
                                .scaleEffect(vipManager.cardStyle == style ? 1.0 : 0.95)
                                .opacity(vipManager.cardStyle == style ? 1.0 : 0.7)
                                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: vipManager.cardStyle) // Elastic stretching effect
                                .shadow(color: vipManager.cardStyle == style ? .white.opacity(0.2) : .clear, radius: 10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(Color.green, lineWidth: vipManager.cardStyle == style ? 3 : 0) // Fit card edge
                                )
                                .onTapGesture {
                                    // Trigger haptic feedback
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                    
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                                        vipManager.updateCardStyle(style)
                                    }
                                }
                                
                                HStack {
                                    Text(style.displayName)
                                        .font(.headline)
                                        .foregroundStyle(vipManager.cardStyle == style ? .white : .gray)
                                    
                                    if vipManager.cardStyle == style {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.headline)
                        .foregroundStyle(vipManager.cardStyle == .monicaPink ? .white : .white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            vipManager.cardStyle == .monicaPink 
                            ? Color(hex: "FF69B4") 
                            : Color(hex: "1E1E1E")
                        )
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
}
}
