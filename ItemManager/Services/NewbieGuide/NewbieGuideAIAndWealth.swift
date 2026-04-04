import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if !WIDGET_EXTENSION
extension FeatureExperienceGuideOverlay {
    var wealthGuideContent: some View {
        GeometryReader { geometry in
            ZStack {
                switch wealthGuideStep {
                case .step1_clickHouseTab:
                    wealthStep1Content(in: geometry)
                case .step2_clickWealthEntry:
                    wealthStep2Content(in: geometry)
                case .step3_divination, .step4_moneyCounting, .step5_wealthStorage:
                    wealthMainTabContent(in: geometry, step: wealthGuideStep)
                }
            }
        }
    }

    func wealthStep1Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let safeAreaBottom = geometry.safeAreaInsets.bottom
        let safeAreaTop = geometry.safeAreaInsets.top
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let fallbackHouseTabFrame = SmallWorldMenuOverlay.buildFallbackFrame(
            screenSize: screenBounds,
            safeAreaTop: safeAreaTop,
            safeAreaBottom: safeAreaBottom,
            isIPad: isIPad
        )

        let houseTabFrame = TabBarItemAnchorResolver.resolvedFrame(
            for: .homeHouseTab,
            preferredTabIndex: 1,
            in: geometry,
            expansion: 0,
            fallback: fallbackHouseTabFrame
        )

        let houseTabRadius = max(34, max(houseTabFrame.width, houseTabFrame.height) / 2)
        let houseTabPawPosition = CGPoint(
            x: min(max(houseTabFrame.midX, 24), screenBounds.width - 24),
            y: min(max(houseTabFrame.midY, 24), screenBounds.height - 24)
        )


        return ZStack {
            HollowMaskView(
                highlightFrame: houseTabFrame,
                highlightType: .circle,
                cornerRadius: houseTabRadius
            )

            HighlightPulseViewNoClick(
                center: CGPoint(x: houseTabFrame.midX, y: houseTabFrame.midY),
                radius: houseTabRadius
            )

            if wealthGuideStep.showCatPaw {
                CatPawTapAnimation(
                    position: houseTabPawPosition,
                    delay: 0.5
                )
                .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                wealthGuideBubble(step: wealthGuideStep)
                    .padding(.bottom, 120)
            }
        }
    }

    func wealthStep2Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let fallbackEntryFrame = CGRect(
            x: (screenBounds.width * 0.52) - 36,
            y: (screenBounds.height * 0.47) - 28,
            width: 72,
            height: 56
        )
        let wealthEntryFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .wealthEntry),
            in: geometry,
            fallback: fallbackEntryFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: wealthEntryFrame,
                highlightType: .roundedRect,
                cornerRadius: 16
            )

            Button {
                NotificationCenter.default.post(
                    name: .navigateToSmallWorldDestination,
                    object: nil,
                    userInfo: ["destination": SmallWorldDestination.wealth(nil)]
                )
            } label: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.001))
                    .frame(width: wealthEntryFrame.width, height: wealthEntryFrame.height)
            }
            .captureGuideInteractionRegion("feature.wealth.entry.hotspot")
            .position(x: wealthEntryFrame.midX, y: wealthEntryFrame.midY)

            RoundedRectHighlightView(
                frame: wealthEntryFrame,
                cornerRadius: 16
            )
            .allowsHitTesting(false)

            if wealthGuideStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: wealthEntryFrame.midX, y: wealthEntryFrame.midY),
                    delay: 0.5
                )
                .opacity(0.45)
                .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                wealthGuideBubble(step: wealthGuideStep)
                    .padding(.bottom, 120)
            }
        }
    }

    func wealthMainTabContent(in geometry: GeometryProxy, step: WealthGuideStep) -> some View {
        let screenBounds = geometry.size
        let fallbackSegmentFrame = CGRect(
            x: (screenBounds.width - 190) / 2,
            y: max(geometry.safeAreaInsets.top + 8, 58),
            width: 190,
            height: 34
        )
        let segmentFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .wealthMainTabSegment),
            in: geometry,
            fallback: fallbackSegmentFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: segmentFrame,
                highlightType: .roundedRect,
                cornerRadius: 10
            )

            RoundedRectHighlightView(
                frame: segmentFrame,
                cornerRadius: 10
            )
            .allowsHitTesting(false)

            VStack {
                Spacer()
                wealthGuideBubble(
                    step: step,
                    onNext: {
                        switch step {
                        case .step3_divination:
                            switchWealthGuideTab(to: .moneyCounting, nextStep: .step4_moneyCounting)
                        case .step4_moneyCounting:
                            switchWealthGuideTab(to: .wealthStorage, nextStep: .step5_wealthStorage)
                        default:
                            break
                        }
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    func switchWealthGuideTab(to tab: WealthMainTab, nextStep: WealthGuideStep) {
        NotificationCenter.default.post(
            name: .wealthGuideSwitchMainTab,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )

        withAnimation(.easeInOut(duration: 0.25)) {
            wealthGuideStep = nextStep
        }
    }

    func wealthGuideBubble(
        step: WealthGuideStep,
        onNext: (() -> Void)? = nil
    ) -> some View {
        let actionTitle: String? = {
            switch step {
            case .step3_divination: return "下一步：数钱"
            case .step4_moneyCounting: return "下一步：安财"
            case .step5_wealthStorage: return "知道了"
            default: return nil
            }
        }()
        let action: (() -> Void)? = {
            if step == .step5_wealthStorage {
                return { guideManager.completeFeatureExperienceGuide() }
            } else if actionTitle != nil {
                return onNext
            }
            return nil
        }()
        return featureStepBubble(
            title: step.title,
            message: step.message,
            currentStep: step.rawValue,
            totalSteps: WealthGuideStep.allCases.count,
            accent: magicPalette.accent,
            actionTitle: actionTitle,
            onSkip: { guideManager.dismissFeatureExperienceGuide() },
            onAction: action
        )
    }

    var aiAnalysisGuideContent: some View {
        GeometryReader { geometry in
            ZStack {
                switch aiAnalysisStep {
                case .preUnlockStep1ReturnToMe:
                    preUnlockStep1Content(in: geometry)
                case .preUnlockStep2ClickVIP:
                    preUnlockStep2Content(in: geometry)
                case .preUnlockStep3Exchange:
                    preUnlockStep3Content(in: geometry)
                case .postUnlockStep1ClickPetChatTab:
                    postUnlockStep1Content(in: geometry)
                case .postUnlockStep2BrowsePets:
                    postUnlockBrowsePetsContent(in: geometry)
                case .postUnlockStep3AdoptNaicha:
                    postUnlockAdoptNaichaContent(in: geometry)
                case .postUnlockStep4NamePet:
                    postUnlockNamePetContent(in: geometry)
                case .postUnlockStep5ClickSearchBar:
                    postUnlockStep5Content(in: geometry)
                case .postUnlockStep6FeatureIntro:
                    postUnlockStep6Content
                }
            }
        }
    }

    func preUnlockStep1Content(in geometry: GeometryProxy) -> some View {
        let progress = aiAnalysisGuideProgress(for: aiAnalysisStep)
        return returnToMeGuideContent(
            in: geometry,
            title: aiAnalysisStep.title,
            message: aiAnalysisStep.message,
            currentStep: progress.current,
            totalSteps: progress.total,
            accent: magicPalette.accent,
            onReturn: handleAIAnalysisGuideReturnAction
        )
    }

    func preUnlockStep2Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let fallbackVIPFrame = CGRect(
            x: 16,
            y: screenBounds.height * 0.16,
            width: screenBounds.width - 32,
            height: VIPManager.shared.isVIP ? 180 : 100
        )
        let vipCardFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .aiAnalysisVIPCard),
            in: geometry,
            fallback: fallbackVIPFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: vipCardFrame,
                highlightType: .roundedRect,
                cornerRadius: 20
            )

            RoundedRectHighlightView(
                frame: vipCardFrame,
                cornerRadius: 20
            )
            .allowsHitTesting(false)

            VStack {
                Spacer()

                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    func preUnlockStep3Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let fallbackExchangeFrame = CGRect(
            x: 20,
            y: screenBounds.height * 0.44,
            width: screenBounds.width - 40,
            height: 56
        )
        let trialConfirmFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .aiAnalysisVIPTrialConfirmButton),
            in: geometry,
            fallback: .zero
        )
        let exchangeButtonFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .aiAnalysisExchangeButton),
            in: geometry,
            fallback: fallbackExchangeFrame
        )
        let shouldGuideTrialConfirm = !VIPManager.shared.isVIP && !trialConfirmFrame.isEmpty
        let targetFrame = shouldGuideTrialConfirm ? trialConfirmFrame : exchangeButtonFrame
        let targetCornerRadius: CGFloat = shouldGuideTrialConfirm ? 16 : 12

        return ZStack {
            HollowMaskView(
                highlightFrame: targetFrame,
                highlightType: .roundedRect,
                cornerRadius: targetCornerRadius
            )

            RoundedRectHighlightView(
                frame: targetFrame,
                cornerRadius: targetCornerRadius
            )
            .allowsHitTesting(false)

            if aiAnalysisStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: targetFrame.midX, y: targetFrame.midY),
                    delay: 0.5
                )
                .allowsHitTesting(false)
            }

            VStack {
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    titleOverride: shouldGuideTrialConfirm ? "确认免费体验" : nil,
                    messageOverride: shouldGuideTrialConfirm
                    ? "点击弹窗里的「确认体验」，先免费体验 VIP 特权，解锁萌宠智能对话。"
                    : nil,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.top, 100)

                Spacer()
            }
        }
    }

    func postUnlockStep1Content(in geometry: GeometryProxy) -> some View {
        print("🐱 [postUnlockStep1Content] 开始渲染")
        let screenBounds = geometry.size
        let safeAreaBottom = geometry.safeAreaInsets.bottom
        let resolvedSafeAreaBottom = max(safeAreaBottom, currentGuideWindowSafeAreaBottom())
        let fallbackTabFrame: CGRect = {
            if #available(iOS 26.0, *) {
                let tabBarHeight: CGFloat = 65
                let ios26BottomCompensation = resolvedSafeAreaBottom * 0.5
                return CGRect(
                    x: (screenBounds.width * 0.875) - 34,
                    y: screenBounds.height - tabBarHeight - 2 - ios26BottomCompensation,
                    width: 68,
                    height: tabBarHeight
                )
            } else {
                let tabBarHeight: CGFloat = 56
                let bottomPadding: CGFloat = resolvedSafeAreaBottom > 0 ? 2 : 4
                let legacyPetChatCenterX = (screenBounds.width * 0.875) - 15
                return CGRect(
                    x: legacyPetChatCenterX - 34,
                    y: screenBounds.height - resolvedSafeAreaBottom - bottomPadding - tabBarHeight,
                    width: 68,
                    height: tabBarHeight
                )
            }
        }()
        print("   screenBounds: \(screenBounds)")
        print("   safeAreaBottom(overlay): \(safeAreaBottom)")
        print("   safeAreaBottom(resolved): \(resolvedSafeAreaBottom)")
        print("   fallbackTabFrame: \(fallbackTabFrame)")

        // 使用 TabBarItemAnchorResolver 获取真实坐标
        let tabFrame = TabBarItemAnchorResolver.resolvedFrame(
            for: .homePetChatTab,
            in: geometry,
            expansion: 0,
            fallback: fallbackTabFrame
        )
        let compensatedTabFrame = compensatedGuideFrameForScale(
            tabFrame,
            screenWidth: screenBounds.width
        )
        let compensatedPulseRadius = compensatedGuideScalarForScale(
            30,
            screenWidth: screenBounds.width
        )
        print("   最终 tabFrame: \(tabFrame)")
        print("   补偿后 tabFrame: \(compensatedTabFrame)")


        return ZStack {
            HollowMaskView(
                highlightFrame: compensatedTabFrame,
                highlightType: .circle,
                cornerRadius: 28
            )

            HighlightPulseViewNoClick(
                center: CGPoint(x: compensatedTabFrame.midX, y: compensatedTabFrame.midY),
                radius: compensatedPulseRadius
            )
            .allowsHitTesting(false)

            if aiAnalysisStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: compensatedTabFrame.midX, y: compensatedTabFrame.midY),
                    delay: 0.5
                )
                .opacity(0.45)
                .allowsHitTesting(false)
            }

            VStack {
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.top, 88)

                Spacer()
            }
        }
    }

    func postUnlockBrowsePetsContent(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let fallbackCarouselFrame = CGRect(
            x: 28,
            y: max(geometry.safeAreaInsets.top + 110, screenBounds.height * 0.15),
            width: screenBounds.width - 56,
            height: min(screenBounds.height * 0.48, 460)
        )
        let carouselFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .petAdoptionCarousel),
            in: geometry,
            fallback: fallbackCarouselFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: carouselFrame,
                highlightType: .roundedRect,
                cornerRadius: 28
            )

            RoundedRectHighlightView(
                frame: carouselFrame,
                cornerRadius: 28
            )
            .allowsHitTesting(false)

            VStack {
                Spacer()

                HorizontalSwipeHintView(
                    title: "请左右滑动",
                    subtitle: "先向右滑动看看别的小伙伴，再向左滑回「奶茶」继续领养。",
                    currentStep: aiAnalysisGuideProgress(for: aiAnalysisStep).current,
                    totalSteps: aiAnalysisGuideProgress(for: aiAnalysisStep).total,
                    accent: magicPalette.accent,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    func postUnlockAdoptNaichaContent(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let fallbackAdoptButtonFrame = CGRect(
            x: 52,
            y: screenBounds.height * 0.63,
            width: screenBounds.width - 104,
            height: 60
        )
        let adoptButtonFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .petAdoptionNaichaButton),
            in: geometry,
            fallback: fallbackAdoptButtonFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: adoptButtonFrame,
                highlightType: .roundedRect,
                cornerRadius: 26
            )

            RoundedRectHighlightView(
                frame: adoptButtonFrame,
                cornerRadius: 26
            )
            .allowsHitTesting(false)

            if aiAnalysisStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: adoptButtonFrame.midX, y: adoptButtonFrame.midY),
                    delay: 0.5
                )
                .opacity(0.45)
                .allowsHitTesting(false)
            }

            VStack {
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.top, 88)

                Spacer()
            }
        }
    }

    func postUnlockNamePetContent(in geometry: GeometryProxy) -> some View {
        let promptFrame = aiAnalysisNamePromptFrame(in: geometry)

        return ZStack {
            HollowMaskView(
                highlightFrame: promptFrame,
                highlightType: .roundedRect,
                cornerRadius: 18
            )

            RoundedRectHighlightView(
                frame: promptFrame,
                cornerRadius: 18
            )
            .allowsHitTesting(false)

            VStack {
                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.top, 88)

                Spacer()
            }
        }
    }

    func postUnlockStep5Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let fallbackGuideOptionFrame = CGRect(
            x: 24,
            y: max(geometry.safeAreaInsets.top + 190, screenBounds.height * 0.42),
            width: screenBounds.width - 48,
            height: 48
        )
        let guideOptionFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .petChatGuideOptionButton),
            in: geometry,
            fallback: fallbackGuideOptionFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: guideOptionFrame,
                highlightType: .roundedRect,
                cornerRadius: 14
            )

            RoundedRectHighlightView(
                frame: guideOptionFrame,
                cornerRadius: 14
            )
            .allowsHitTesting(false)

            if aiAnalysisStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: guideOptionFrame.midX, y: guideOptionFrame.midY),
                    delay: 0.5
                )
                .opacity(0.45)
                .allowsHitTesting(false)
            }

            VStack {
                Spacer()

                aiAnalysisBubble(
                    step: aiAnalysisStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }

    var postUnlockStep6Content: some View {
        VStack {
            Spacer()

            aiAnalysisBubble(
                step: aiAnalysisStep,
                onSkip: {
                    guideManager.dismissFeatureExperienceGuide()
                },
                onComplete: {
                    guideManager.completeFeatureExperienceGuide()
                }
            )
            .padding(.bottom, 120)
        }
    }

    func aiAnalysisGuideProgress(for step: AIAnalysisGuideStep) -> (current: Int, total: Int) {
        let steps: [AIAnalysisGuideStep]
        switch step.flow {
        case .preUnlock:
            steps = AIAnalysisGuideStep.preUnlockCases
        case .postUnlock:
            steps = aiAnalysisRequiresPetAdoptionGuide
                ? [
                    .postUnlockStep1ClickPetChatTab,
                    .postUnlockStep2BrowsePets,
                    .postUnlockStep3AdoptNaicha,
                    .postUnlockStep4NamePet,
                    .postUnlockStep5ClickSearchBar,
                    .postUnlockStep6FeatureIntro
                ]
                : [
                    .postUnlockStep1ClickPetChatTab,
                    .postUnlockStep5ClickSearchBar,
                    .postUnlockStep6FeatureIntro
                ]
        }

        return (
            current: (steps.firstIndex(of: step) ?? 0) + 1,
            total: steps.count
        )
    }

    func aiAnalysisNamePromptFrame(in geometry: GeometryProxy) -> CGRect {
        let dialogWidth: CGFloat = 270
        let dialogHeight: CGFloat = 180
        let centeredX = (geometry.size.width - dialogWidth) / 2
        let centeredY = (geometry.size.height - dialogHeight) / 2
        let safeAreaTop = max(geometry.safeAreaInsets.top, aiCurrentGuideWindowSafeAreaTop())
        let safeAreaBottom = max(geometry.safeAreaInsets.bottom, currentGuideWindowSafeAreaBottom())
        let effectiveKeyboardOverlap = max(0, guideKeyboardOverlap - safeAreaBottom)

        guard effectiveKeyboardOverlap > 0 else {
            return CGRect(x: centeredX, y: centeredY, width: dialogWidth, height: dialogHeight)
        }

        let topPadding = safeAreaTop + 20
        let visibleBottom = geometry.size.height - effectiveKeyboardOverlap - 16
        let maxY = max(topPadding, visibleBottom - dialogHeight)
        let visibleCenteredY = topPadding + max(0, (visibleBottom - topPadding - dialogHeight) / 2)
        let adjustedY = min(centeredY, max(topPadding, min(visibleCenteredY, maxY)))

        return CGRect(x: centeredX, y: adjustedY, width: dialogWidth, height: dialogHeight)
    }

    func aiGuideTargetFrame(
        globalFrame: CGRect?,
        in geometry: GeometryProxy,
        fallback: CGRect
    ) -> CGRect {
        guard let globalFrame, globalFrame.width > 0, globalFrame.height > 0 else {
            return guideManager.shouldUseGuideFallbackFrames ? fallback : .zero
        }

        // 直接返回 global frame，因为 overlay window 与主应用窗口使用相同的坐标系
        // overlay window 会自动对齐到主应用窗口，不需要额外的坐标转换
        return globalFrame
    }

    func compensatedGuideFrameForScale(_ frame: CGRect, screenWidth: CGFloat) -> CGRect {
        let scale = GuideAdaptiveScale.factor(screenWidth: screenWidth)
        guard scale > 0 else { return frame }
        let compensatedWidth = frame.width / scale
        let compensatedHeight = frame.height / scale
        return CGRect(
            x: frame.midX - compensatedWidth / 2,
            y: frame.midY - compensatedHeight / 2,
            width: compensatedWidth,
            height: compensatedHeight
        )
    }

    func compensatedGuideScalarForScale(_ value: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let scale = GuideAdaptiveScale.factor(screenWidth: screenWidth)
        guard scale > 0 else { return value }
        return value / scale
    }

    func currentGuideWindowSafeAreaBottom() -> CGFloat {
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
        #else
        return 0
        #endif
    }

    func aiCurrentGuideWindowSafeAreaTop() -> CGFloat {
        #if canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
        #else
        return 0
        #endif
    }

    func aiAnalysisBubble(
        step: AIAnalysisGuideStep,
        titleOverride: String? = nil,
        messageOverride: String? = nil,
        completionButtonTitleOverride: String? = nil,
        onSkip: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) -> some View {
        let progress = aiAnalysisGuideProgress(for: step)
        let actionTitle: String? = step.showsCompletionButton
            ? (completionButtonTitleOverride ?? step.completionButtonTitle)
            : nil
        return featureStepBubble(
            title: titleOverride ?? step.title,
            message: messageOverride ?? step.message,
            currentStep: progress.current,
            totalSteps: progress.total,
            accent: magicPalette.accent,
            actionTitle: actionTitle,
            onSkip: onSkip,
            onAction: step.showsCompletionButton ? onComplete : nil
        )
    }
}
#endif
