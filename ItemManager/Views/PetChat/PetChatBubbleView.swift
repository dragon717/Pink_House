import SwiftUI

struct PetChatBubble: View {
    let message: PetChatMessage
    let petName: String
    let onCardTap: (Clothing) -> Void
    let onSearchResultTap: (Clothing) -> Void
    let onOutfitTap: (OutfitSuggestionData) -> Void
    let onWidgetAction: (PetWidgetOption, UUID) -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAllResults = false
    @State private var showingReportButton = false
    
    private var currentPetCharacter: PetCharacter {
        guard let petId = PetDataManager.shared.status.selectedPetId,
              let character = PetCharacter(rawValue: petId) else {
            return .naicha
        }
        return character
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !message.isUser {
                petAvatarView
            } else {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if !message.isUser && message.isAIGenerated {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("AI 生成")
                            .font(.caption2)
                    }
                    .foregroundStyle(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme).opacity(0.8))
                    .padding(.leading, 4)
                }
                
                switch message.type {
                case .text, .thinking:
                    textBubble
                case .wardrobeCard:
                    if let clothing = message.clothing {
                        wardrobeCardBubble(clothing)
                    } else {
                        textBubble
                    }
                case .statistics:
                    if let stats = message.statistics {
                        statisticsBubble(stats)
                    } else {
                        textBubble
                    }
                case .colorMatch:
                    if let colorRec = message.colorRecommendation {
                        colorMatchBubble(colorRec)
                    } else {
                        textBubble
                    }
                case .searchResults:
                    if let results = message.searchResults {
                        searchResultsBubble(results)
                    } else {
                        textBubble
                    }
                case .outfitSuggestion:
                    if let suggestion = message.outfitSuggestion {
                        outfitSuggestionBubble(suggestion)
                    } else {
                        textBubble
                    }
                }

                if !standaloneWidgets.isEmpty {
                    PetGenerativeWidgetHost(widgets: standaloneWidgets) { option in
                        onWidgetAction(option, message.id)
                    }
                    .frame(maxWidth: 320, alignment: message.isUser ? .trailing : .leading)
                }
                
                HStack(spacing: 12) {
                    Text(formatTimestamp(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.gray.opacity(0.8))
                    
                    if !message.isUser && message.isAIGenerated && showingReportButton {
                        Button(action: {
                            showingReportButton = false
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.bubble")
                                    .font(.caption2)
                                Text("举报")
                                    .font(.caption2)
                            }
                            .foregroundStyle(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme))
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.leading, message.isUser ? 0 : 4)
            }
            
            if message.isUser {
                userAvatarView
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
    }
    
    private var petAvatarView: some View {
        Image(defaultPetExpressionImageName)
            .resizable()
            .scaledToFill()
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme).opacity(0.3), lineWidth: 2)
            )
    }
    
    private var userAvatarView: some View {
        UserAvatarView(
            givenName: AuthenticationManager.shared.givenName,
            familyName: AuthenticationManager.shared.familyName,
            customAvatarPath: AuthenticationManager.shared.customAvatarPath,
            size: 40
        )
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private var skinTheme: PetChatSkinTheme {
        themeManager.petChatSkinTheme
    }

    private var bubbleCornerRadius: CGFloat {
        skinTheme.cornerRadius
    }

    private var aiBubbleTextColor: Color {
        skinTheme.resolvedAssistantBubbleTextColor(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var userBubbleTextColor: Color {
        skinTheme.resolvedUserBubbleTextColor(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var embeddedQuickOptionWidgets: [PetWidgetData] {
        guard !message.isUser,
              (message.type == .text || message.type == .thinking),
              let widgets = message.widgets,
              !widgets.isEmpty,
              widgets.allSatisfy({ $0.type == .quickOptions }) else {
            return []
        }
        return widgets
    }

    private var standaloneWidgets: [PetWidgetData] {
        guard let widgets = message.widgets, !widgets.isEmpty else { return [] }
        return embeddedQuickOptionWidgets.isEmpty ? widgets : []
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

    @ViewBuilder
    private func bubbleBackground(isUser: Bool) -> some View {
        if skinTheme == .classic {
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .fill(skinTheme.resolvedAssistantBubbleBackground(themeManager: themeManager, colorScheme: colorScheme))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        } else if isUser {
            let bubbleColors = skinTheme.resolvedUserBubbleColors(themeManager: themeManager, colorScheme: colorScheme)
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .fill(
                    LinearGradient(
                        colors: bubbleColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme).opacity(0.25),
                    radius: 6,
                    x: 0,
                    y: 2
                )
        } else {
            let bgColor = skinTheme.resolvedAssistantBubbleBackground(themeManager: themeManager, colorScheme: colorScheme)
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: bubbleCornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: skinTheme.resolvedAssistantStrokeColors(themeManager: themeManager, colorScheme: colorScheme),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme).opacity(0.2),
                    radius: 5,
                    x: 0,
                    y: 2
                )
        }
    }
    
    private var textBubble: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            if !message.isUser, let imageName = message.imageName {
                let resolvedImageName = resolvedBubbleImageName(from: imageName)
                if let image = UIImage(named: resolvedImageName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .cornerRadius(12)
                        .overlay(alignment: .bottomTrailing) {
                            PetStampView()
                                .scaleEffect(0.5)
                                .padding(4)
                        }
                } else {
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
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.isUser ? userBubbleTextColor : aiBubbleTextColor)

                if !embeddedQuickOptionWidgets.isEmpty {
                    PetGenerativeWidgetHost(widgets: embeddedQuickOptionWidgets) { option in
                        onWidgetAction(option, message.id)
                    }
                    .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bubbleBackground(isUser: message.isUser))
        }
        .frame(maxWidth: embeddedQuickOptionWidgets.isEmpty ? 280 : 320, alignment: message.isUser ? .trailing : .leading)
        .onLongPressGesture {
            if !message.isUser && message.isAIGenerated {
                withAnimation {
                    showingReportButton = true
                }
            }
        }
    }
    
    private func wardrobeCardBubble(_ clothing: Clothing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)
            
            Button {
                onCardTap(clothing)
            } label: {
                HStack(spacing: 12) {
                    if let firstImagePath = clothing.imagePaths.first {
                        AsyncLocalImageView(
                            fileName: firstImagePath,
                            displaySize: CGSize(width: 60, height: 60),
                            contentMode: .fill,
                            cornerRadius: 8,
                            placeholderColor: themeManager.tertiaryTextColor.opacity(0.2)
                        )
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(themeManager.tertiaryTextColor.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "tshirt")
                                    .foregroundStyle(themeManager.secondaryTextColor)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clothing.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .foregroundStyle(aiBubbleTextColor)
                        
                        if let brand = clothing.brand {
                            Text(brand.name)
                                .font(.caption)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }
                        
                        Text("¥\(NSDecimalNumber(decimal: clothing.unitTotalPrice).stringValue)")
                            .font(.caption)
                            .foregroundStyle(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                }
                .padding(12)
                .background(skinTheme.resolvedAssistantCardBackground(themeManager: themeManager, colorScheme: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bubbleBackground(isUser: false))
        .frame(maxWidth: 320, alignment: .leading)
    }
    
    private func statisticsBubble(_ stats: WardrobeStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)
            
            VStack(spacing: 10) {
                statRow(icon: "hanger", title: "总件数", value: "\(stats.totalCount) 件")
                statRow(icon: "yensign.circle", title: "总价值", value: "¥\(NSDecimalNumber(decimal: stats.totalValue).stringValue)")
                
                if let mostExpensive = stats.mostExpensiveItem {
                    statRow(icon: "crown", title: "最贵单品", value: mostExpensive.name)
                }
                
                if stats.depositPlanCount > 0 {
                    statRow(icon: "tag", title: "心愿尾款", value: "\(stats.depositPlanCount) 款")
                    statRow(icon: "creditcard", title: "待付尾款", value: "¥\(NSDecimalNumber(decimal: stats.totalBalance).stringValue)")
                }
            }
            .padding(12)
            .background(skinTheme.resolvedAssistantCardBackground(themeManager: themeManager, colorScheme: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bubbleBackground(isUser: false))
        .frame(maxWidth: 320, alignment: .leading)
    }
    
    private func statRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme))
                .frame(width: 20)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(aiBubbleTextColor)
                .lineLimit(1)
        }
    }
    
    private func colorMatchBubble(_ colorRec: ColorRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)
            
            HStack(spacing: 8) {
                colorCircle(colorRec.primaryColor, label: "主色")
                colorCircle(colorRec.secondaryColor, label: "辅色")
                colorCircle(colorRec.accentColor, label: "点缀")
            }
            
            Text(colorRec.reasoning)
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bubbleBackground(isUser: false))
        .frame(maxWidth: 320, alignment: .leading)
    }
    
    private func colorCircle(_ colorName: String, label: String) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(colorFromName(colorName))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(themeManager.tertiaryTextColor.opacity(0.3), lineWidth: 1)
                )
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(themeManager.secondaryTextColor)
        }
    }
    
    private func colorFromName(_ name: String) -> Color {
        let colorMap: [String: Color] = [
            "粉色": .pink, "红色": .red, "橙色": .orange, "黄色": .yellow,
            "绿色": .green, "蓝色": .blue, "紫色": .purple, "黑色": .black,
            "白色": .white, "灰色": .gray, "棕色": .brown, "米色": Color(red: 0.96, green: 0.91, blue: 0.84)
        ]
        return colorMap[name] ?? .pink
    }
    
    private func searchResultsBubble(_ results: [Clothing]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)
            
            VStack(spacing: 8) {
                ForEach(showAllResults ? results : Array(results.prefix(3))) { clothing in
                    Button {
                        onSearchResultTap(clothing)
                    } label: {
                        HStack(spacing: 10) {
                            if let firstImagePath = clothing.imagePaths.first {
                                AsyncLocalImageView(
                                    fileName: firstImagePath,
                                    displaySize: CGSize(width: 40, height: 40),
                                    contentMode: .fill,
                                    cornerRadius: 6,
                                    placeholderColor: themeManager.tertiaryTextColor.opacity(0.2)
                                )
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(themeManager.tertiaryTextColor.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "tshirt")
                                            .font(.caption)
                                            .foregroundStyle(themeManager.secondaryTextColor)
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clothing.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .foregroundStyle(aiBubbleTextColor)
                                
                                Text("¥\(NSDecimalNumber(decimal: clothing.price).stringValue)")
                                    .font(.caption2)
                                    .foregroundStyle(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        }
                        .padding(8)
                        .background(skinTheme.resolvedAssistantCardBackground(themeManager: themeManager, colorScheme: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if results.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showAllResults.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showAllResults ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                            Text(showAllResults ? "收起" : "还有 \(results.count - 3) 件...")
                                .font(.caption)
                        }
                        .foregroundStyle(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .background(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bubbleBackground(isUser: false))
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func outfitSuggestionBubble(_ suggestion: OutfitSuggestionData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.description)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)

            HStack(spacing: 8) {
                Label(suggestion.style, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme).opacity(0.1))
                    .clipShape(Capsule())

                Label(suggestion.occasion, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(themeManager.secondaryTextColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("推荐单品")
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)

                ForEach(suggestion.clothings.prefix(4)) { clothing in
                    Button {
                        onCardTap(clothing)
                    } label: {
                        HStack(spacing: 8) {
                            if let firstPath = clothing.imagePaths.first,
                               let image = ImageManager.shared.loadImage(fileName: firstPath) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(themeManager.tertiaryTextColor.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "tshirt")
                                            .foregroundStyle(themeManager.tertiaryTextColor)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(clothing.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundStyle(aiBubbleTextColor)
                                Text(clothing.brand?.name ?? "未知品牌")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.secondaryTextColor)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(skinTheme.resolvedAssistantCardBackground(themeManager: themeManager, colorScheme: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Button {
                onOutfitTap(suggestion)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text("魔法贴纸")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [
                            skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme),
                            skinTheme.resolvedAssistantAccentColor(themeManager: themeManager, colorScheme: colorScheme).mixed(with: themeManager.secondaryTextColor, amount: 0.3)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bubbleBackground(isUser: false))
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func outfitItemsPreview(_ outfit: Outfit) -> some View {
        let items = outfit.items ?? []
        return HStack(spacing: 8) {
            ForEach(items.prefix(4), id: \.id) { item in
                if let cutout = item.cutout,
                   let image = ImageManager.shared.loadImage(fileName: cutout.imagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "tshirt")
                                .foregroundStyle(.gray)
                        )
                }
            }

            if items.count > 4 {
                Text("+\(items.count - 4)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
