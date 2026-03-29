import SwiftUI

struct PetAdoptionView: View {
    @ObservedObject var viewModel: PetViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var currentSelection: Int = 0
    
    // Naming state
    @State private var showNameInput = false
    @State private var inputName = ""
    @State private var selectedPet: PetCharacter?
    
    // Alert state
    @State private var showInsufficientFundsAlert = false
    @State private var missingCurrencyName = ""
    
    var body: some View {
        GeometryReader { geo in
            let layout = PetAdoptionContainerLayout(size: geo.size, safeAreaInsets: geo.safeAreaInsets)

            ZStack {
                LiquidBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer(minLength: layout.verticalInset)
                    
                    TabView(selection: $currentSelection) {
                        ForEach(0..<PetCharacter.allCases.count, id: \.self) { index in
                            let pet = PetCharacter.allCases[index]
                            let (price, currency) = viewModel.getAdoptionPrice(for: pet)
                            
                            PetAdoptionCard(
                                pet: pet,
                                isOwned: viewModel.status.ownedPetIds.contains(pet.id),
                                price: price,
                                currency: currency,
                                onAdopt: {
                                    // Check balance
                                    if price > 0 {
                                        var canAfford = false
                                        switch currency {
                                        case .meowCoin: canAfford = viewModel.status.meowCoin >= price
                                        case .fishCoin: canAfford = viewModel.status.fishCoin >= price
                                        case .boneCoin: canAfford = viewModel.status.boneCoin >= price
                                        }
                                        
                                        if !canAfford {
                                            missingCurrencyName = currency.rawValue
                                            showInsufficientFundsAlert = true
                                            return
                                        }
                                    }
                                    
                                    selectedPet = pet
                                    inputName = "" // Reset name
                                    showNameInput = true
                                }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(width: layout.cardWidth, height: layout.cardHeight)
                    .frame(maxWidth: .infinity)
                    
                    Spacer(minLength: layout.verticalInset)
                }
                .padding(.horizontal, layout.horizontalInset)
            }
        }
        .navigationTitle("领养伙伴")
        .navigationBarTitleDisplayMode(.inline)
        .alert("为它起个名字", isPresented: $showNameInput) {
            TextField("名字", text: $inputName)
            Button("确定") {
                if let pet = selectedPet {
                    let name = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.adoptPet(pet, name: name.isEmpty ? nil : name)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("给你的小伙伴起个独特的名字吧！")
        }
        .alert("余额不足", isPresented: $showInsufficientFundsAlert) {
            Button("好的", role: .cancel) { }
        } message: {
            Text("您需要更多的 \(missingCurrencyName) 才能领养这只小可爱。")
        }
    }
}

struct PetAdoptionCard: View {
    let pet: PetCharacter
    let isOwned: Bool
    let price: Int
    let currency: PetCurrency
    let onAdopt: () -> Void
    
    var body: some View {
        GeometryReader { geo in
            let layout = PetAdoptionCardLayout(size: geo.size)
            let frame = geo.frame(in: .global)
            let minX = frame.minX
            let rotation = Double(minX / -20)
            
            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                
                ViewThatFits(in: .vertical) {
                    adoptionCardContent(layout: layout, minX: minX, expandsVertically: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ScrollView(.vertical, showsIndicators: false) {
                        adoptionCardContent(layout: layout.compactVariant, minX: minX, expandsVertically: false)
                            .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(layout.outerPadding)
            .rotation3DEffect(
                .degrees(rotation),
                axis: (x: 0, y: 1, z: 0)
            )
        }
        .padding(12)
    }

    @ViewBuilder
    private func adoptionCardContent(layout: PetAdoptionCardLayout, minX: CGFloat, expandsVertically: Bool) -> some View {
        VStack(spacing: layout.contentSpacing) {
            Image(pet.portraitImageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: layout.imageMaxWidth, maxHeight: layout.imageHeight)
                .frame(height: layout.imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: layout.imageCornerRadius))
                .shadow(radius: 5)
                .scaleEffect(1.0 + abs(minX / 1000.0))
            
            VStack(spacing: layout.textSpacing) {
                Text(pet.displayName)
                    .font(.system(size: layout.titleFontSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.85)
                    .lineLimit(1)
                
                Text(pet.description)
                    .font(.system(size: layout.descriptionFontSize))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, layout.textHorizontalPadding)
            
            if expandsVertically {
                Spacer(minLength: layout.bottomSpacing)
            }
            
            if isOwned {
                Text("已领养")
                    .font(.system(size: layout.badgeFontSize, weight: .black))
                    .foregroundColor(.pink.opacity(0.8))
                    .padding(.horizontal, layout.badgeHorizontalPadding)
                    .padding(.vertical, layout.badgeVerticalPadding)
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.badgeCornerRadius)
                            .stroke(.pink.opacity(0.8), lineWidth: 4)
                    )
                    .rotationEffect(.degrees(-15))
                    .padding(.bottom, layout.bottomSpacing)
            } else {
                Button(action: onAdopt) {
                    HStack(spacing: 4) {
                        Text("领养")
                            .font(.system(size: layout.buttonTitleFontSize, weight: .bold))
                        
                        if price > 0 {
                            Text("(\(price)\(currency.rawValue))")
                                .font(.system(size: layout.buttonDetailFontSize, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, layout.buttonVerticalPadding)
                    .background(
                        LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(radius: 5)
                }
                .padding(.horizontal, layout.buttonHorizontalPadding)
                .padding(.bottom, layout.bottomSpacing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, layout.topPadding)
        .padding(.horizontal, layout.contentHorizontalPadding)
        .padding(.bottom, layout.bottomPadding)
    }
}

private struct PetAdoptionContainerLayout {
    let horizontalInset: CGFloat
    let verticalInset: CGFloat
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    init(size: CGSize, safeAreaInsets: EdgeInsets) {
        let usableWidth = max(size.width - safeAreaInsets.leading - safeAreaInsets.trailing, 300)
        let usableHeight = max(size.height - safeAreaInsets.top - safeAreaInsets.bottom, 420)

        let isCompactHeight = usableHeight < 700

        horizontalInset = (size.width * 0.06).clamped(to: 16...32)
        verticalInset = (usableHeight * (isCompactHeight ? 0.02 : 0.04)).clamped(to: 10...28)

        let availableWidth = max(usableWidth - horizontalInset * 2, 280)
        let availableHeight = max(usableHeight - verticalInset * 2, 340)

        cardWidth = min(availableWidth, 560)
        cardHeight = min(availableHeight * (isCompactHeight ? 0.95 : 0.9), 620)
    }
}

private struct PetAdoptionCardLayout {
    let size: CGSize
    let outerPadding: CGFloat
    let contentHorizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let contentSpacing: CGFloat
    let textSpacing: CGFloat
    let textHorizontalPadding: CGFloat
    let imageHeight: CGFloat
    let imageMaxWidth: CGFloat
    let imageCornerRadius: CGFloat
    let titleFontSize: CGFloat
    let descriptionFontSize: CGFloat
    let bottomSpacing: CGFloat
    let badgeFontSize: CGFloat
    let badgeHorizontalPadding: CGFloat
    let badgeVerticalPadding: CGFloat
    let badgeCornerRadius: CGFloat
    let buttonHorizontalPadding: CGFloat
    let buttonVerticalPadding: CGFloat
    let buttonTitleFontSize: CGFloat
    let buttonDetailFontSize: CGFloat

    init(size: CGSize, compact: Bool = false) {
        self.size = size
        let shortestSide = min(size.width, size.height)
        outerPadding = (shortestSide * (compact ? 0.03 : 0.045)).clamped(to: 10...20)
        contentHorizontalPadding = (size.width * (compact ? 0.045 : 0.055)).clamped(to: 14...24)
        topPadding = (size.height * (compact ? 0.04 : 0.06)).clamped(to: 14...30)
        bottomPadding = (size.height * (compact ? 0.03 : 0.05)).clamped(to: 12...24)
        contentSpacing = (size.height * (compact ? 0.02 : 0.04)).clamped(to: 8...20)
        textSpacing = compact ? 6 : 8
        textHorizontalPadding = (size.width * (compact ? 0.02 : 0.04)).clamped(to: 8...18)
        imageHeight = min((size.height * (compact ? 0.34 : 0.42)).clamped(to: 120...260), size.width * 0.78)
        imageMaxWidth = (size.width * (compact ? 0.72 : 0.8)).clamped(to: 140...320)
        imageCornerRadius = (shortestSide * 0.05).clamped(to: 16...22)
        titleFontSize = (size.width * (compact ? 0.055 : 0.065)).clamped(to: 20...28)
        descriptionFontSize = (size.width * (compact ? 0.034 : 0.038)).clamped(to: 13...17)
        bottomSpacing = (size.height * (compact ? 0.015 : 0.03)).clamped(to: 6...16)
        badgeFontSize = (size.width * (compact ? 0.05 : 0.06)).clamped(to: 18...24)
        badgeHorizontalPadding = compact ? 16 : 20
        badgeVerticalPadding = compact ? 8 : 10
        badgeCornerRadius = compact ? 8 : 10
        buttonHorizontalPadding = (size.width * (compact ? 0.05 : 0.09)).clamped(to: 18...40)
        buttonVerticalPadding = (size.height * (compact ? 0.025 : 0.03)).clamped(to: 10...16)
        buttonTitleFontSize = (size.width * (compact ? 0.045 : 0.05)).clamped(to: 17...21)
        buttonDetailFontSize = (size.width * (compact ? 0.036 : 0.04)).clamped(to: 14...17)
    }

    var compactVariant: PetAdoptionCardLayout {
        PetAdoptionCardLayout(size: size, compact: true)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
