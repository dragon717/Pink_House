
import SwiftUI

struct BanknoteView: View {
    let denomination: Denomination
    let currency: CurrencyType
    var showShadow: Bool = true

    // Access the shared manager
    // In SwiftUI with Observation, accessing properties of an @Observable singleton in body
    // should trigger updates if the view is within a tracking scope (which Views are).
    private var appearanceManager = WealthAppearanceManager.shared

    // 货币代码文本
    private var currencyCodeText: String {
        switch currency {
        case .rmb: return "RMB"
        case .jpy: return "JPY"
        case .usd: return "USD"
        case .gold: return "GOLD"
        case .silver: return "SILVER"
        }
    }

    init(denomination: Denomination, currency: CurrencyType, showShadow: Bool = true) {
        self.denomination = denomination
        self.currency = currency
        self.showShadow = showShadow
    }
    
    var body: some View {
        ZStack {
            // Background
            if let customImage = appearanceManager.getCustomImage(currency: currency, denominationValue: denomination.value) {
                Image(uiImage: customImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 160, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: showShadow ? 1 : 0, x: 0, y: showShadow ? 1 : 0)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(denomination.color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: showShadow ? 1 : 0, x: 0, y: showShadow ? 1 : 0)
                
                // Pattern/Texture (Simplified) - Only show on default background
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
            }
            
            // Value Text
            // Only show text if NO custom image is used
            if appearanceManager.getCustomImage(currency: currency, denominationValue: denomination.value) == nil {
                VStack {
                    HStack {
                        Text("\(denomination.value)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(currencyCodeText)
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
        BanknoteView(
            denomination: Denomination(value: 100, color: Color(red: 0.1, green: 0.4, blue: 0.2), name: "100"),
            currency: .usd
        )
        BanknoteView(
            denomination: Denomination(value: 2, color: Color(red: 0.3, green: 0.4, blue: 0.6), name: "2"),
            currency: .usd
        )
    }
    .padding()
    .background(Color.gray)
}
