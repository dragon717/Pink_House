import SwiftUI

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
        let tabBarHeight: CGFloat = 56
        let fallbackHouseTabFrame = CGRect(
            x: (screenBounds.width * 0.375) - 34,
            y: screenBounds.height - geometry.safeAreaInsets.bottom - tabBarHeight,
            width: 68,
            height: tabBarHeight
        )
        let capturedHouseTabFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .homeHouseTab),
            in: geometry,
            fallback: fallbackHouseTabFrame
        )
        let houseTabFrame = CGRect(
            x: capturedHouseTabFrame.midX - 34,
            y: capturedHouseTabFrame.midY - (tabBarHeight / 2),
            width: 68,
            height: tabBarHeight
        )
        let houseTabPawPosition = CGPoint(
            x: min(max(houseTabFrame.midX, 24), screenBounds.width - 24),
            y: min(max(houseTabFrame.midY, 24), screenBounds.height - 24)
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: houseTabFrame,
                highlightType: .circle,
                cornerRadius: 28
            )

            HighlightPulseViewNoClick(
                center: CGPoint(x: houseTabFrame.midX, y: houseTabFrame.midY),
                radius: 34
            )

            if wealthGuideStep.showCatPaw && !guideManager.isPadGuideLayout {
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
        WealthGuideBubbleView(
            step: step,
            onSkip: {
                guideManager.dismissFeatureExperienceGuide()
            },
            onNext: onNext,
            onComplete: {
                guideManager.completeFeatureExperienceGuide()
            }
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
                case .postUnlockStep2ClickSearchBar:
                    postUnlockStep2Content(in: geometry)
                case .postUnlockStep3FeatureIntro:
                    postUnlockStep3Content
                }
            }
        }
    }

    func preUnlockStep1Content(in geometry: GeometryProxy) -> some View {
        let backButtonFrame = returnGuideBackButtonFrame(in: geometry)

        return ZStack {
            HollowMaskView(
                highlightFrame: backButtonFrame,
                highlightType: .circle,
                cornerRadius: 22
            )

            HighlightPulseViewNoClick(
                center: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                radius: 28
            )

            if aiAnalysisStep.showCatPaw && !guideManager.isPadGuideLayout {
                CatPawTapAnimation(
                    position: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                    delay: 0.5
                )
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
        let exchangeButtonFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .aiAnalysisExchangeButton),
            in: geometry,
            fallback: fallbackExchangeFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: exchangeButtonFrame,
                highlightType: .roundedRect,
                cornerRadius: 12
            )

            RoundedRectHighlightView(
                frame: exchangeButtonFrame,
                cornerRadius: 12
            )
            .allowsHitTesting(false)

            if aiAnalysisStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: exchangeButtonFrame.midX, y: exchangeButtonFrame.midY),
                    delay: 0.5
                )
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
                .padding(.top, 100)

                Spacer()
            }
        }
    }

    func postUnlockStep1Content(in geometry: GeometryProxy) -> some View {
        let tabGuideYOffset: CGFloat = -18
        let fallbackTabFrame = petChatTabFallbackFrame(in: geometry)
        let rawTabFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .homePetChatTab),
            in: geometry,
            fallback: fallbackTabFrame
        )
        let tabFrame = CGRect(
            x: rawTabFrame.midX - 34,
            y: rawTabFrame.midY - 28 + tabGuideYOffset,
            width: 68,
            height: 56
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: tabFrame,
                highlightType: .circle,
                cornerRadius: 28
            )

            HighlightPulseViewNoClick(
                center: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
                radius: 34
            )
            .allowsHitTesting(false)

            if aiAnalysisStep.showCatPaw && !guideManager.isPadGuideLayout {
                CatPawTapAnimation(
                    position: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
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

    func postUnlockStep2Content(in geometry: GeometryProxy) -> some View {
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

    var postUnlockStep3Content: some View {
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

    func petChatTabFallbackFrame(in geometry: GeometryProxy) -> CGRect {
        let screenBounds = geometry.size
        let tabBarHeight: CGFloat = 56
        return CGRect(
            x: (screenBounds.width * 0.875) - 34,
            y: screenBounds.height - geometry.safeAreaInsets.bottom - tabBarHeight,
            width: 68,
            height: tabBarHeight
        )
    }

    func aiGuideTargetFrame(
        globalFrame: CGRect?,
        in geometry: GeometryProxy,
        fallback: CGRect
    ) -> CGRect {
        guard let globalFrame, globalFrame.width > 0, globalFrame.height > 0 else {
            return guideManager.shouldUseGuideFallbackFrames ? fallback : .zero
        }

        let overlayGlobalOrigin = geometry.frame(in: .global).origin
        return CGRect(
            x: globalFrame.minX - overlayGlobalOrigin.x,
            y: globalFrame.minY - overlayGlobalOrigin.y,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }

    func aiAnalysisBubble(
        step: AIAnalysisGuideStep,
        onSkip: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) -> some View {
        AIAnalysisGuideBubbleView(
            step: step,
            onSkip: onSkip,
            onComplete: onComplete
        )
    }
}
#endif
