import SwiftUI

struct VIPCardView: View {
    let vipNumber: String
    let expireDate: Date?
    let isVIP: Bool
    
    @State private var shimmerOffset: CGFloat = -300
    
    var body: some View {
        ZStack {
            // 1. Base Background: Deep Matte Black/Grey
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "2C2C2C"), // Charcoal
                            Color(hex: "121212"), // Almost Black
                            Color(hex: "000000")  // Pure Black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
            
            // 2. Subtle Texture (Optional - noise can be simulated with overlay if needed, keeping it clean for now)
            
            // 3. Golden Flow Effect (Shimmer)
            GeometryReader { geometry in
                LinearGradient(
                    colors: [
                        .clear,
                        Color(hex: "FFD700").opacity(0.2), // Faint Gold
                        Color(hex: "FFFACD").opacity(0.4), // Bright Highlight
                        Color(hex: "FFD700").opacity(0.2), // Faint Gold
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 150) // Width of the shimmer beam
                .rotationEffect(.degrees(20)) // Slight angle
                .offset(x: shimmerOffset)
                .blur(radius: 5)
                .blendMode(.overlay)
                .mask(RoundedRectangle(cornerRadius: 20))
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        shimmerOffset = geometry.size.width + 300
                    }
                }
            }
            
            // 4. Refined Golden Border
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(hex: "B8860B"), // Dark Gold
                            Color(hex: "FFD700"), // Bright Gold
                            Color(hex: "B8860B")  // Dark Gold
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "crown.fill")
                        .font(.title)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FFD700"), Color(hex: "FFFACD")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .orange.opacity(0.5), radius: 5)
                    
                    Text("少女心愿 VIP")
                        .font(.custom("Zapfino", size: 20))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FFD700"), Color(hex: "FFFACD"), Color(hex: "B8860B")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                    
                    Spacer()
                    
                    if isVIP {
                        Text("黑金尊享")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                    Capsule()
                                        .stroke(Color(hex: "FFD700"), lineWidth: 1)
                                }
                            )
                            .foregroundStyle(Color(hex: "FFD700"))
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                
                Spacer()
                
                // VIP Number
                if isVIP {
                    Text(formatVIPNumber(vipNumber))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FFFACD"), Color(hex: "FFD700"), Color(hex: "B8860B")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.black.opacity(0.5), radius: 2, x: 1, y: 1)
                        .padding(.horizontal, 24)
                } else {
                    Text("加入尊贵会员，解锁专属特权")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 24)
                }
                
                Spacer()
                
                // Footer
                HStack {
                    VStack(alignment: .leading) {
                        Text("VALID THRU")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(hex: "B8860B"))
                        
                        if let date = expireDate, isVIP {
                            Text(date.formatted(date: .numeric, time: .omitted))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                        } else {
                            Text("--/--")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Chip
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(colors: [Color(hex: "FFD700"), Color(hex: "B8860B")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "simcard.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24)
                                .foregroundStyle(.black.opacity(0.4))
                                .rotationEffect(.degrees(90))
                        )
                        .shadow(radius: 2)
                }
                .padding(.bottom, 24)
                .padding(.horizontal, 24)
            }
        }
        .frame(height: 220)
    }
    
    private func formatVIPNumber(_ number: String) -> String {
        // Format as groups of 4: 8888 8888
        var result = ""
        for (index, char) in number.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result.append(char)
        }
        return result
    }
}

