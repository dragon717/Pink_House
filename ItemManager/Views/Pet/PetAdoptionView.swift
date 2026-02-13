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
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Cards
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
                    .frame(height: min(geo.size.height * 0.8, 600)) // 自适应高度，但不超过600
                    
                    Spacer()
                }
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
            let frame = geo.frame(in: .global)
            let minX = frame.minX
            // 简单的视差/景深效果计算
            let rotation = Double(minX / -20)
            
            ZStack {
                // Card Background
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                
                VStack(spacing: 20) {
                    // Portrait
                    Image(pet.portraitImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 5)
                        // 景深效果：根据滚动位置轻微缩放
                        .scaleEffect(1.0 + abs(minX/1000.0))
                    
                    // Info
                    VStack(spacing: 8) {
                        Text(pet.displayName)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        
                        Text(pet.description)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Action Button
                    if isOwned {
                        // Stamp
                        ZStack {
                            Text("已领养")
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(.pink.opacity(0.8))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(.pink.opacity(0.8), lineWidth: 4)
                                )
                                .rotationEffect(.degrees(-15))
                        }
                        .padding(.bottom, 20)
                    } else {
                        Button(action: onAdopt) {
                            HStack(spacing: 4) {
                                Text("领养")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                
                                if price > 0 {
                                    Text("(\(price)\(currency.rawValue))")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                            .shadow(radius: 5)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 20)
                    }
                }
                .padding(.top, 30)
            }
            .padding(20)
            .rotation3DEffect(
                .degrees(rotation),
                axis: (x: 0, y: 1, z: 0)
            )
        }
        .padding(20)
    }
}
