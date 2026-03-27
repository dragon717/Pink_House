import SwiftUI

#if !WIDGET_EXTENSION
extension FeatureExperienceGuideOverlay {
    var backupGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFeatureExperienceGuide()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(magicPalette.accent)

                Text("数据备份")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(magicPalette.primaryText)

                Text("保护你的数据安全")
                    .font(.subheadline)
                    .foregroundStyle(magicPalette.secondaryText)

                if showingFullDescription {
                    Text("支持本地备份和iCloud云端同步~\n\n本地备份：导出数据文件到本地存储\niCloud同步：在所有Apple设备间自动同步")
                        .font(.caption)
                        .foregroundStyle(magicPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(magicPalette.quickOptionText)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFeatureExperienceGuide()
                    } label: {
                        Text("知道了")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(magicPalette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(magicPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    var cloudSyncGuideContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    guideManager.dismissFeatureExperienceGuide()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(magicPalette.accent)

                Text("iCloud云端同步")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(magicPalette.primaryText)

                Text("数据自动同步到云端")
                    .font(.subheadline)
                    .foregroundStyle(magicPalette.secondaryText)

                if showingFullDescription {
                    Text("开启后，你的所有数据将在所有Apple设备间自动同步~\n\n换手机也不用担心数据丢失！")
                        .font(.caption)
                        .foregroundStyle(magicPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingFullDescription.toggle()
                        }
                    } label: {
                        Text(showingFullDescription ? "收起" : "了解更多")
                            .font(.subheadline)
                            .foregroundStyle(magicPalette.quickOptionText)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }

                    Button {
                        guideManager.completeFeatureExperienceGuide()
                    } label: {
                        Text("知道了")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(magicPalette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(magicPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    var batchImportGuideContent: some View {
        wardrobeGuideContent(accent: wardrobeGuideAccent(for: .batchImport))
    }

    var filterClassicGuideContent: some View {
        personalPreferenceGuideContent
    }

    var privacyDisplayGuideContent: some View {
        privacyDisplayStepGuideContent
    }

    var tagBrandFieldGuideContent: some View {
        tagBrandFieldStepGuideContent
    }

    var themeGuideContent: some View {
        themeCustomizeGuideContent
    }

    var widgetCustomizeGuideContent: some View {
        GeometryReader { geometry in
            ZStack {
                switch widgetCustomizeStep {
                case .step1_returnToMe:
                    widgetStep1Content(in: geometry)
                case .step2_scrollToWidget:
                    widgetStep2Content
                case .step3_clickWidgetEntry:
                    widgetStep3Content(in: geometry)
                case .step4_widgetExplanation:
                    widgetStep4Content
                }
            }
        }
    }

    func widgetStep1Content(in geometry: GeometryProxy) -> some View {
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

            if widgetCustomizeStep.showCatPaw && !guideManager.isPadGuideLayout {
                CatPawTapAnimation(
                    position: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                    delay: 0.5
                )
            }

            if guideManager.lastKnownHomeTab == "me" {
                Button {
                    handleWidgetGuideReturnAction()
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 72, height: 72)
                }
                .captureGuideInteractionRegion("feature.widget.return.hotspot")
                .position(x: backButtonFrame.midX, y: backButtonFrame.midY)
            }

            VStack {
                Spacer()

                widgetCustomizeBubble(
                    step: widgetCustomizeStep,
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

    var widgetStep2Content: some View {
        ZStack {
            WidgetScrollHintView()
                .allowsHitTesting(false)

            VStack {
                Spacer()

                widgetCustomizeBubble(
                    step: widgetCustomizeStep,
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

    func widgetStep3Content(in geometry: GeometryProxy) -> some View {
        let screenBounds = geometry.size
        let fallbackWidgetFrame = CGRect(
            x: 16,
            y: screenBounds.height * 0.58,
            width: (screenBounds.width - 48) / 2,
            height: 92
        )
        let widgetEntryFrame = aiGuideTargetFrame(
            globalFrame: guideManager.guideTargetFrame(for: .widgetCustomizeEntry),
            in: geometry,
            fallback: fallbackWidgetFrame
        )

        return ZStack {
            HollowMaskView(
                highlightFrame: widgetEntryFrame,
                highlightType: .roundedRect,
                cornerRadius: 16
            )

            RoundedRectHighlightView(
                frame: widgetEntryFrame,
                cornerRadius: 16
            )
            .allowsHitTesting(false)

            if widgetCustomizeStep.showCatPaw {
                CatPawTapAnimation(
                    position: CGPoint(x: widgetEntryFrame.midX, y: widgetEntryFrame.midY),
                    delay: 0.5
                )
                .allowsHitTesting(false)
            }

            VStack {
                widgetCustomizeBubble(
                    step: widgetCustomizeStep,
                    onSkip: {
                        guideManager.dismissFeatureExperienceGuide()
                    },
                    onComplete: {
                        guideManager.completeFeatureExperienceGuide()
                    }
                )
                .padding(.top, 110)

                Spacer()
            }
        }
    }

    var widgetStep4Content: some View {
        VStack {
            Spacer()

            widgetCustomizeBubble(
                step: widgetCustomizeStep,
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

    func widgetCustomizeBubble(
        step: WidgetCustomizeGuideStep,
        onSkip: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) -> some View {
        WidgetCustomizeGuideBubbleView(
            step: step,
            onSkip: onSkip,
            onComplete: onComplete
        )
    }
}
#endif
