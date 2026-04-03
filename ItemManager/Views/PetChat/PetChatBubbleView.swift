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
    @State private var showingReportButton = false

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var contentBubbleMaxWidth: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return min(screenWidth * 0.55, 520)
        }
        return min(screenWidth - 104, 340)
    }

    private var textBubbleMaxWidth: CGFloat {
        if embeddedQuickOptionWidgets.isEmpty {
            return min(contentBubbleMaxWidth, screenWidth * 0.72)
        }
        return contentBubbleMaxWidth
    }
    
    private var speakerPetCharacter: PetCharacter {
        message.speakerPetCharacter ?? .naicha
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

                if let expressionImageName = standaloneExpressionImageName {
                    standaloneExpressionView(imageName: expressionImageName)
                }
                
                switch message.type {
                case .text, .thinking:
                    if shouldMergeStandaloneWidgets {
                        mergedBubble(mainContentMaxWidth: contentBubbleMaxWidth) {
                            textContent
                        }
                    } else {
                        textBubble
                    }
                case .wardrobeCard:
                    if let clothing = message.clothing {
                        if shouldMergeStandaloneWidgets {
                            mergedBubble(mainContentMaxWidth: contentBubbleMaxWidth) {
                                wardrobeCardContent(clothing)
                            }
                        } else {
                            wardrobeCardBubble(clothing)
                        }
                    } else {
                        textBubble
                    }
                case .statistics:
                    if let stats = message.statistics {
                        if shouldMergeStandaloneWidgets {
                            mergedBubble(mainContentMaxWidth: contentBubbleMaxWidth) {
                                statisticsContent(stats)
                            }
                        } else {
                            statisticsBubble(stats)
                        }
                    } else {
                        textBubble
                    }
                case .colorMatch:
                    if let colorRec = message.colorRecommendation {
                        if shouldMergeStandaloneWidgets {
                            mergedBubble(mainContentMaxWidth: contentBubbleMaxWidth) {
                                colorMatchContent(colorRec)
                            }
                        } else {
                            colorMatchBubble(colorRec)
                        }
                    } else {
                        textBubble
                    }
                case .searchResults:
                    if let results = message.searchResults {
                        if shouldMergeStandaloneWidgets {
                            mergedBubble(mainContentMaxWidth: contentBubbleMaxWidth) {
                                searchResultsContent(results)
                            }
                        } else {
                            searchResultsBubble(results)
                        }
                    } else {
                        textBubble
                    }
                case .outfitSuggestion:
                    if let suggestion = message.outfitSuggestion {
                        if shouldMergeStandaloneWidgets {
                            mergedBubble(mainContentMaxWidth: contentBubbleMaxWidth) {
                                outfitSuggestionContent(suggestion)
                            }
                        } else {
                            outfitSuggestionBubble(suggestion)
                        }
                    } else {
                        textBubble
                    }
                }

                if !shouldMergeStandaloneWidgets && !standaloneWidgets.isEmpty {
                    PetGenerativeWidgetHost(widgets: standaloneWidgets) { option in
                        onWidgetAction(option, message.id)
                    }
                    .frame(maxWidth: contentBubbleMaxWidth, alignment: message.isUser ? .trailing : .leading)
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

    private var shouldMergeStandaloneWidgets: Bool {
        !message.isUser && !standaloneWidgets.isEmpty
    }

    private var defaultPetExpressionImageName: String {
        if UIImage(named: speakerPetCharacter.quickOptionIconName) != nil {
            return speakerPetCharacter.quickOptionIconName
        }
        return speakerPetCharacter.happyImageName
    }

    private func fallbackEmotionImageName(for imageName: String) -> String? {
        if imageName.hasPrefix("playful_") {
            return speakerPetCharacter.happyImageName
        }
        if imageName.hasPrefix("sad_") {
            return speakerPetCharacter.sleepyImageName
        }
        if imageName.hasPrefix("confused_") || imageName == "confused" {
            return speakerPetCharacter.confusedImageName
        }
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

    private var standaloneExpressionImageName: String? {
        guard !message.isUser, message.type == .text || message.type == .thinking else {
            return nil
        }
        if let explicitImageName = message.imageName, !explicitImageName.isEmpty {
            return resolvedBubbleImageName(from: explicitImageName)
        }
        guard let meaning = detectPetChatExpressionMeaning(in: message.text) else {
            return nil
        }
        return resolvedBubbleImageName(from: speakerPetCharacter.chatExpressionImageName(for: meaning))
    }

    @ViewBuilder
    private func standaloneExpressionView(imageName: String) -> some View {
        if let image = UIImage(named: imageName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 110, maxHeight: 110)
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .scale))
        }
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
    
    private func mergedBubble<Content: View>(
        mainContentMaxWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 12) {
            content()

            PetGenerativeWidgetHost(widgets: standaloneWidgets) { option in
                onWidgetAction(option, message.id)
            }
            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bubbleBackground(isUser: message.isUser))
        .frame(maxWidth: mainContentMaxWidth, alignment: message.isUser ? .trailing : .leading)
        .onLongPressGesture {
            if !message.isUser && message.isAIGenerated {
                withAnimation {
                    showingReportButton = true
                }
            }
        }
    }

    private var textContent: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                bubbleText(expandsToBubbleWidth: !embeddedQuickOptionWidgets.isEmpty)

                if !embeddedQuickOptionWidgets.isEmpty {
                    PetGenerativeWidgetHost(widgets: embeddedQuickOptionWidgets) { option in
                        onWidgetAction(option, message.id)
                    }
                    .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func bubbleText(expandsToBubbleWidth: Bool) -> some View {
        let cleanedText = PetGenerativePromptBuilder.sanitizeMessageText(message.text)
        let text = Text(cleanedText)
            .font(.subheadline)
            .foregroundStyle(message.isUser ? userBubbleTextColor : aiBubbleTextColor)
            .multilineTextAlignment(message.isUser ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)

        if expandsToBubbleWidth {
            text.frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        } else {
            text
        }
    }

    private var textBubble: some View {
        textContent
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bubbleBackground(isUser: message.isUser))
        
        .frame(maxWidth: textBubbleMaxWidth, alignment: message.isUser ? .trailing : .leading)
        .onLongPressGesture {
            if !message.isUser && message.isAIGenerated {
                withAnimation {
                    showingReportButton = true
                }
            }
        }
    }
    
    private func wardrobeCardContent(_ clothing: Clothing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button {
                onCardTap(clothing)
            } label: {
                HStack(alignment: .top, spacing: 12) {
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
                            .lineLimit(3)
                            .foregroundStyle(aiBubbleTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        
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
    }

    private func wardrobeCardBubble(_ clothing: Clothing) -> some View {
        wardrobeCardContent(clothing)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bubbleBackground(isUser: false))
            .frame(maxWidth: contentBubbleMaxWidth, alignment: .leading)
    }
    
    private func statisticsContent(_ stats: WardrobeStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
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
    }

    private func statisticsBubble(_ stats: WardrobeStats) -> some View {
        statisticsContent(stats)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bubbleBackground(isUser: false))
            .frame(maxWidth: contentBubbleMaxWidth, alignment: .leading)
    }
    
    private func statRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top) {
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
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func colorMatchContent(_ colorRec: ColorRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
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
    }

    private func colorMatchBubble(_ colorRec: ColorRecommendation) -> some View {
        colorMatchContent(colorRec)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bubbleBackground(isUser: false))
            .frame(maxWidth: contentBubbleMaxWidth, alignment: .leading)
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
    
    private func searchResultsContent(_ results: [Clothing]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            clothingCarousel(results, onTap: onSearchResultTap)
        }
    }

    private func searchResultsBubble(_ results: [Clothing]) -> some View {
        searchResultsContent(results)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bubbleBackground(isUser: false))
            .frame(maxWidth: contentBubbleMaxWidth, alignment: .leading)
    }

    private func outfitSuggestionContent(_ suggestion: OutfitSuggestionData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.description)
                .font(.subheadline)
                .foregroundStyle(aiBubbleTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

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

                clothingCarousel(Array(suggestion.clothings.prefix(8)), onTap: onCardTap)
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
    }

    private func outfitSuggestionBubble(_ suggestion: OutfitSuggestionData) -> some View {
        outfitSuggestionContent(suggestion)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bubbleBackground(isUser: false))
            .frame(maxWidth: contentBubbleMaxWidth, alignment: .leading)
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

    private func clothingCarousel(_ clothings: [Clothing], onTap: @escaping (Clothing) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(clothings) { clothing in
                    Button {
                        onTap(clothing)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            clothingCarouselImage(for: clothing)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(clothing.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(aiBubbleTextColor)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let brandName = clothing.brand?.name,
                                   !brandName.isEmpty {
                                    Text(brandName)
                                        .font(.caption2)
                                        .foregroundStyle(themeManager.secondaryTextColor)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .frame(width: 128, alignment: .topLeading)
                        .background(skinTheme.resolvedAssistantCardBackground(themeManager: themeManager, colorScheme: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func clothingCarouselImage(for clothing: Clothing) -> some View {
        if let firstImagePath = clothing.imagePaths.first {
            AsyncLocalImageView(
                fileName: firstImagePath,
                displaySize: CGSize(width: 112, height: 112),
                contentMode: .fill,
                cornerRadius: 10,
                placeholderColor: themeManager.tertiaryTextColor.opacity(0.2)
            )
            .frame(width: 112, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(themeManager.tertiaryTextColor.opacity(0.2))
                .frame(width: 112, height: 112)
                .overlay(
                    Image(systemName: "tshirt")
                        .foregroundStyle(themeManager.secondaryTextColor)
                )
        }
    }
}
