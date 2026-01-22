
import SwiftUI

struct BanknoteView: View {
    let denomination: Denomination
    let currency: CurrencyType
    var showShadow: Bool = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(denomination.color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: showShadow ? 1 : 0, x: 0, y: showShadow ? 1 : 0)
                
                // Pattern/Texture (Simplified)
                HStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Spacer()
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                }
                .padding(8)
                
                // Value Text
                VStack {
                    HStack {
                        Text("\(denomination.value)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(currency == .rmb ? "RMB" : "JPY")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(4)
                    
                    Spacer()
                    
                    Text("\(denomination.value)")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                    
                    Spacer()
                    
                    HStack {
                        Spacer()
                        Text("\(denomination.value)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(4)
                }
            }
        }
        .frame(width: 160, height: 80) // Standard aspect ratio approx 2:1
    }
}

#Preview {
    VStack {
        BanknoteView(
            denomination: Denomination(value: 100, color: .red, name: "100"),
            currency: .rmb
        )
        BanknoteView(
            denomination: Denomination(value: 10000, color: .brown, name: "10000"),
            currency: .jpy
        )
    }
    .padding()
    .background(Color.gray)
}
