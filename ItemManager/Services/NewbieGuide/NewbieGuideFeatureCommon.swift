import SwiftUI

#if !WIDGET_EXTENSION
extension FeatureExperienceGuideOverlay {
    func guideDebugFrameDescription(_ frame: CGRect?) -> String {
        guard let frame else { return "nil" }
        return String(
            format: "(x:%.1f,y:%.1f,w:%.1f,h:%.1f,maxY:%.1f)",
            frame.minX,
            frame.minY,
            frame.width,
            frame.height,
            frame.maxY
        )
    }

    func logCustomColorGuide(_ message: String) {
        let screenBounds = UIScreen.main.bounds
        print(
            "[Guide][CustomColor] step=\(customColorPersonalizationGuideStep.rawValue) " +
            "title=\(customColorPersonalizationGuideStep.title) " +
            "tab=\(guideManager.lastKnownHomeTab) " +
            "screen=\(Int(screenBounds.width))x\(Int(screenBounds.height)) " +
            "\(message)"
        )
    }

    func logCustomColorVisibilityCheck(label: String, frame: CGRect?) -> Bool {
        guard let frame else {
            logCustomColorGuide("\(label) visibilityCheck frame=nil visible=false")
            return false
        }

        let visibleBounds = UIScreen.main.bounds.insetBy(dx: 0, dy: 120)
        let visible = frame.width > 1 &&
        frame.height > 1 &&
        frame.maxY > visibleBounds.minY &&
        frame.minY < visibleBounds.maxY

        logCustomColorGuide(
            "\(label) visibilityCheck frame=\(guideDebugFrameDescription(frame)) " +
            "visibleBounds=\(guideDebugFrameDescription(visibleBounds)) visible=\(visible)"
        )
        return visible
    }

    enum WardrobeGuideStep2Target {
        case manualCreate
        case batchImport
        case either
    }

    enum SpaceBookGuideLocation {
        case unknown
        case wardrobeHome
        case ootdShelf
        case ootdPlanarDetail
        case spaceShelf
        case spaceDetail
    }

    func wardrobeGuideAccent(for feature: FeatureItem) -> Color {
        switch feature {
        case .ootd:
            return .orange
        case .ootdDefaultBook:
            return .pink
        case .calendar:
            return .purple
        case .spaceBook:
            return .blue
        case .batchImport:
            return .green
        default:
            return .green
        }
    }

    func preUnlockWardrobeGuideContentIfNeeded(for feature: FeatureItem) -> AnyView? {
        guard usesPreUnlockWardrobeGuide(for: feature) else { return nil }
        return AnyView(wardrobeGuideContent(accent: wardrobeGuideAccent(for: feature)))
    }

    func wardrobeGuideStep2Target(for feature: FeatureItem) -> WardrobeGuideStep2Target? {
        if feature == .batchImport {
            return FeatureUnlockManager.shared.isUnlocked(feature) ? .batchImport : .manualCreate
        }
        return usesPreUnlockWardrobeGuide(for: feature) ? .either : nil
    }

    func isPreUnlockWardrobeGuideReusableFeature(_ feature: FeatureItem) -> Bool {
        [.ootd, .ootdDefaultBook, .calendar, .batchImport, .spaceBook].contains(feature)
    }

    var magicStickerGuideTotalSteps: Int {
        2
    }

    func magicStickerGuideDisplayStep(for step: MagicStickerGuideStep) -> Int {
        step.rawValue
    }

    func returnGuideBackButtonFrame(in geometry: GeometryProxy) -> CGRect {
        CGRect(
            x: 16,
            y: max(geometry.safeAreaInsets.top + 8, 58),
            width: 44,
            height: 44
        )
    }

    @ViewBuilder
    func guideContent(for feature: FeatureItem) -> some View {
        switch feature {
        case .dataBackup:
            backupGuideContent
        case .cloudSync:
            cloudSyncGuideContent
        case .batchImport:
            batchImportGuideContent
        case .themeCustomize:
            themeGuideContent
        case .customColorPersonalization:
            customColorPersonalizationGuideContent
        case .localFileBackupRestore:
            localFileBackupRestoreGuideContent
        case .exportCSV:
            exportCSVGuideContent
        case .cloudFileBackupRestore:
            cloudFileBackupRestoreGuideContent
        case .widgetCustomize:
            widgetCustomizeGuideContent
        case .filterClassic:
            filterClassicGuideContent
        case .privacyDisplay:
            privacyDisplayGuideContent
        case .tagBrandFieldDisplay:
            tagBrandFieldGuideContent
        case .spaceBook:
            spaceBookGuideContent
        case .batchEdit:
            batchEditGuideContent
        case .ootd:
            ootdGuideContent
        case .ootdDefaultBook:
            magicStickerGuideContent
        case .calendar:
            calendarGuideContent
        case .wealth:
            wealthGuideContent
        case .aiAnalysis:
            aiAnalysisGuideContent
        default:
            genericGuideContent(for: feature)
        }
    }

    func resetGuideStepState() {
        guard let feature = guideManager.currentFeatureExperienceFeature else { return }

        // 重置所有共享状态，防止不同功能之间的状态污染
        showingFullDescription = false
        didDismissAIAnalysisReturnStep = false
        aiAnalysisRequiresPetAdoptionGuide = false
        didBrowseAwayFromNaichaInAIAnalysisGuide = false
        themeScrollStepStartedAt = nil
        customColorScrollStepStartedAt = nil
        customColorPersonalizationScrollStepStartedAt = nil
        isSpaceBookCreationPromptVisible = false
        isOotdBookCreationPromptVisible = false
        guideKeyboardOverlap = 0
        hasSpaceBooksForGuide = false
        hasNonDefaultSpaceBooksForGuide = false
        hasSpaceBookPagesForGuide = false
        didOpenBatchEditMoreMenu = false
        didOpenSpatialImportMenu = false
        spaceBookGuideLocation = .unknown

        // 重置所有步骤状态到初始值，避免缓存污染
        aiAnalysisStep = .preUnlockStep1ReturnToMe
        widgetCustomizeStep = .step1_returnToMe
        wardrobeAddGuideStep = .step1_clickAddButton
        themeCustomizeGuideStep = .step1_returnToMe
        localFileBackupRestoreGuideStep = .step1_returnToMe
        exportCSVGuideStep = .step1_returnToMe
        cloudFileBackupRestoreGuideStep = .step1_returnToMe
        customColorPersonalizationGuideStep = .step1_returnToMe
        personalPreferenceGuideStep = .step1_returnToMe
        privacyDisplayGuideStep = .step1_returnToMe
        tagBrandFieldGuideStep = .step1_returnToMe
        ootdGuideStep = .step1_clickOotdEntry
        calendarGuideStep = .step1_clickCalendarEntry
        magicStickerGuideStep = .step1_clickMagicStickerEntry
        batchEditGuideStep = .step1_clickMoreMenu
        spaceBookGuideStep = .preUnlockStep1_clickWardrobeOotdEntry
        wealthGuideStep = .step1_clickHouseTab

        // 根据当前功能设置正确的初始状态
        switch feature {
        case .aiAnalysis:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                aiAnalysisRequiresPetAdoptionGuide = PetDataManager.shared.status.ownedPetIds.isEmpty
                aiAnalysisStep = resolvedAIAnalysisPostUnlockEntryStep()
            } else {
                aiAnalysisStep = .preUnlockStep1ReturnToMe
            }
        case .widgetCustomize:
            widgetCustomizeStep = .step1_returnToMe
        case .themeCustomize:
            themeCustomizeGuideStep = .step1_returnToMe
        case .customColorPersonalization:
            customColorPersonalizationGuideStep = .step1_returnToMe
        case .localFileBackupRestore:
            localFileBackupRestoreGuideStep = .step1_returnToMe
        case .exportCSV:
            exportCSVGuideStep = .step1_returnToMe
        case .cloudFileBackupRestore:
            cloudFileBackupRestoreGuideStep = .step1_returnToMe
        case .filterClassic:
            personalPreferenceGuideStep = .step1_returnToMe
        case .privacyDisplay:
            privacyDisplayGuideStep = .step1_returnToMe
        case .tagBrandFieldDisplay:
            tagBrandFieldGuideStep = .step1_returnToMe
        case .batchImport:
            wardrobeAddGuideStep = .step1_clickAddButton
        case .ootdDefaultBook:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                magicStickerGuideStep = .step1_clickMagicStickerEntry
            } else {
                wardrobeAddGuideStep = .step1_clickAddButton
            }
        case .ootd:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                ootdGuideStep = .step1_clickOotdEntry
            } else {
                wardrobeAddGuideStep = .step1_clickAddButton
            }
        case .calendar:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                calendarGuideStep = .step1_clickCalendarEntry
            } else {
                wardrobeAddGuideStep = .step1_clickAddButton
            }
        case .spaceBook:
            syncSpaceBookGuideLocationFromVisibleTargets()
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                spaceBookGuideStep = .step1_clickWardrobeOotdEntry
            } else if FeatureUnlockManager.shared.isUnlocked(.ootd) {
                spaceBookGuideStep = .preUnlockStep1_clickWardrobeOotdEntry
            } else {
                // ootd未解锁：先引导用户解锁ootd（衣橱预引导）
                wardrobeAddGuideStep = .step1_clickAddButton
            }
        case .batchEdit:
            batchEditGuideStep = .step1_clickMoreMenu
        case .wealth:
            wealthGuideStep = .step1_clickHouseTab
            if guideManager.guideTargetFrame(for: .wealthEntry) != nil {
                wealthGuideStep = .step2_clickWealthEntry
            }
            if guideManager.guideTargetFrame(for: .wealthMainTabSegment) != nil {
                wealthGuideStep = .step3_divination
            }
        default:
            break
        }
    }

    func syncSpaceBookGuideLocationFromVisibleTargets() {
        let inferredLocation: SpaceBookGuideLocation
        let hasOotdShelfAnchors =
            guideManager.guideTargetFrame(for: .ootdShelfMoreMenuButton) != nil ||
            guideManager.guideTargetFrame(for: .spaceBookModeTabs) != nil
        let hasSpaceShelfAnchors =
            guideManager.guideTargetFrame(for: .spaceBookShelfMoreMenuButton) != nil
        let hasOotdDetailAnchors =
            guideManager.guideTargetFrame(for: .ootdDetailBackButton) != nil ||
            guideManager.guideTargetFrame(for: .ootdDetailMoreMenuButton) != nil
        let hasSpaceDetailAnchors =
            guideManager.guideTargetFrame(for: .spaceBookDetailMoreMenuButton) != nil ||
            guideManager.guideTargetFrame(for: .spaceBookFirstPageCard) != nil

        // 返回动画结束后，旧详情页的 target 可能会短暂残留；
        // 只要当前已经重新拿到了页签/书架层 target，就优先认定为上层列表界面。
        if hasOotdShelfAnchors {
            inferredLocation = .ootdShelf
        } else if hasSpaceShelfAnchors {
            inferredLocation = .spaceShelf
        } else if hasOotdDetailAnchors {
            inferredLocation = .ootdPlanarDetail
        } else if hasSpaceDetailAnchors {
            inferredLocation = .spaceDetail
        } else if guideManager.guideTargetFrame(for: .wardrobeOotdEntry) != nil || currentTab == "wardrobe" {
            inferredLocation = .wardrobeHome
        } else {
            inferredLocation = .unknown
        }

        spaceBookGuideLocation = inferredLocation
    }

    func shouldGuideUnlockPendingOotdForSpaceBook() -> Bool {
        guard !FeatureUnlockManager.shared.isUnlocked(.spaceBook) else { return false }
        guard !FeatureUnlockManager.shared.isUnlocked(.ootd) else { return false }
        return FeatureUnlockManager.shared.checkUnlockCondition(.ootd).met
    }

    func shouldShowSpaceBookReturnGuide() -> Bool {
        guard spaceBookGuideLocation == .ootdPlanarDetail else { return false }

        let hasShelfLevelTargets =
            guideManager.guideTargetFrame(for: .spaceBookModeTabs) != nil ||
            guideManager.guideTargetFrame(for: .ootdShelfMoreMenuButton) != nil

        return !hasShelfLevelTargets
    }

    func advanceWealthToMainTabGuideIfNeeded() {
        guard guideManager.currentFeatureExperienceFeature == .wealth else { return }
        guard wealthGuideStep.rawValue < WealthGuideStep.step3_divination.rawValue else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            wealthGuideStep = .step3_divination
        }
    }

    func advanceWidgetGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .widgetCustomize else { return }
        guard widgetCustomizeStep == .step1_returnToMe else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            widgetCustomizeStep = .step2_scrollToWidget
        }

        if guideManager.guideTargetFrame(for: .widgetCustomizeEntry) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                      widgetCustomizeStep == .step2_scrollToWidget else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    widgetCustomizeStep = .step3_clickWidgetEntry
                }
            }
        }
    }

    func advanceThemeGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .themeCustomize else { return }
        guard themeCustomizeGuideStep == .step1_returnToMe else { return }

        themeScrollStepStartedAt = Date()
        withAnimation(.easeInOut(duration: 0.3)) {
            themeCustomizeGuideStep = .step2_scrollToThemeEntry
        }

        if guideManager.guideTargetFrame(for: .themeCustomizeEntry) != nil {
            advanceThemeGuideToClickStepWithMinimumDwell()
        }
    }

    func advanceCustomColorPersonalizationGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .customColorPersonalization else { return }
        guard customColorPersonalizationGuideStep == .step1_returnToMe else { return }

        let existingThemeEntryFrame = guideManager.guideTargetFrame(for: .themeCustomizeEntry)
        logCustomColorGuide(
            "advanceFromReturnStep existingThemeEntryFrame=\(guideDebugFrameDescription(existingThemeEntryFrame))"
        )

        customColorScrollStepStartedAt = Date()
        withAnimation(.easeInOut(duration: 0.3)) {
            customColorPersonalizationGuideStep = .step2_scrollToThemeEntry
        }

        if existingThemeEntryFrame != nil {
            _ = logCustomColorVisibilityCheck(
                label: "advanceFromReturnStep.themeEntryAlreadyCaptured",
                frame: existingThemeEntryFrame
            )
            advanceCustomColorGuideToClickStepWithMinimumDwell()
        } else {
            logCustomColorGuide("advanceFromReturnStep theme entry not captured yet; waiting for onChange")
        }
    }

    func advanceLocalFileBackupRestoreGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .localFileBackupRestore else { return }
        guard localFileBackupRestoreGuideStep == .step1_returnToMe else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            localFileBackupRestoreGuideStep = .step2_scrollToSystemSettings
        }

        if let frame = guideManager.guideTargetFrame(for: .systemSettingsEntry),
           isGuideTargetVisibleOnScreen(frame) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                      localFileBackupRestoreGuideStep == .step2_scrollToSystemSettings else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    localFileBackupRestoreGuideStep = .step3_clickSystemSettings
                }
            }
        }
    }

    func advanceExportCSVGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .exportCSV else { return }
        guard exportCSVGuideStep == .step1_returnToMe else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            exportCSVGuideStep = .step2_scrollToSystemSettings
        }

        if let frame = guideManager.guideTargetFrame(for: .systemSettingsEntry),
           isGuideTargetVisibleOnScreen(frame) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard guideManager.currentFeatureExperienceFeature == .exportCSV,
                      exportCSVGuideStep == .step2_scrollToSystemSettings else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    exportCSVGuideStep = .step3_clickSystemSettings
                }
            }
        }
    }

    func advanceCloudFileBackupRestoreGuideFromReturnStep() {
        guard guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore else { return }
        guard cloudFileBackupRestoreGuideStep == .step1_returnToMe else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            cloudFileBackupRestoreGuideStep = .step2_clickAccountSync
        }
    }

    func advanceThemeGuideToClickStepWithMinimumDwell(minimumDwell: TimeInterval = 2.0) {
        guard guideManager.currentFeatureExperienceFeature == .themeCustomize else { return }
        guard themeCustomizeGuideStep == .step2_scrollToThemeEntry else { return }

        let start = themeScrollStepStartedAt ?? Date()
        if themeScrollStepStartedAt == nil {
            themeScrollStepStartedAt = start
        }

        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, minimumDwell - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            guard guideManager.currentFeatureExperienceFeature == .themeCustomize,
                  themeCustomizeGuideStep == .step2_scrollToThemeEntry else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                themeCustomizeGuideStep = .step3_clickThemeEntry
            }
            themeScrollStepStartedAt = nil
        }
    }

    func advanceCustomColorGuideToClickStepWithMinimumDwell(minimumDwell: TimeInterval = 2.0) {
        guard guideManager.currentFeatureExperienceFeature == .customColorPersonalization else { return }
        guard customColorPersonalizationGuideStep == .step2_scrollToThemeEntry else { return }

        let start = customColorScrollStepStartedAt ?? Date()
        if customColorScrollStepStartedAt == nil {
            customColorScrollStepStartedAt = start
        }

        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, minimumDwell - elapsed)
        let themeEntryFrame = guideManager.guideTargetFrame(for: .themeCustomizeEntry)
        let isVisible = logCustomColorVisibilityCheck(
            label: "advanceToClick.minimumDwellScheduled",
            frame: themeEntryFrame
        )
        logCustomColorGuide(
            String(
                format: "advanceToClick schedule elapsed=%.2f remaining=%.2f themeEntryVisible=%@",
                elapsed,
                remaining,
                String(isVisible)
            )
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            guard guideManager.currentFeatureExperienceFeature == .customColorPersonalization,
                  customColorPersonalizationGuideStep == .step2_scrollToThemeEntry else { return }
            let latestFrame = guideManager.guideTargetFrame(for: .themeCustomizeEntry)
            let latestVisible = logCustomColorVisibilityCheck(
                label: "advanceToClick.minimumDwellCompleted",
                frame: latestFrame
            )
            logCustomColorGuide(
                "advanceToClick promotingToStep3 latestThemeEntryFrame=\(guideDebugFrameDescription(latestFrame)) " +
                "latestVisible=\(latestVisible)"
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                customColorPersonalizationGuideStep = .step3_clickThemeEntry
            }
            customColorScrollStepStartedAt = nil
        }
    }

    func beginCustomColorPersonalizationScrollStep() {
        customColorPersonalizationScrollStepStartedAt = Date()
        logCustomColorGuide("entered step5 scrollToPersonalization")
    }

    func advanceCustomColorGuideToPersonalizationExplanationWithMinimumDwell(minimumDwell: TimeInterval = 1.2) {
        guard guideManager.currentFeatureExperienceFeature == .customColorPersonalization else { return }
        guard customColorPersonalizationGuideStep == .step5_scrollToPersonalization else { return }

        let start = customColorPersonalizationScrollStepStartedAt ?? Date()
        if customColorPersonalizationScrollStepStartedAt == nil {
            customColorPersonalizationScrollStepStartedAt = start
        }

        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, minimumDwell - elapsed)
        let personalizationFrame = guideManager.guideTargetFrame(for: .themeCustomPersonalizationEntry)
        let isVisible = logCustomColorVisibilityCheck(
            label: "advanceToPersonalization.minimumDwellScheduled",
            frame: personalizationFrame
        )
        logCustomColorGuide(
            String(
                format: "advanceToPersonalization schedule elapsed=%.2f remaining=%.2f personalizationVisible=%@",
                elapsed,
                remaining,
                String(isVisible)
            )
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            guard guideManager.currentFeatureExperienceFeature == .customColorPersonalization,
                  customColorPersonalizationGuideStep == .step5_scrollToPersonalization else { return }
            let latestFrame = guideManager.guideTargetFrame(for: .themeCustomPersonalizationEntry)
            let latestVisible = logCustomColorVisibilityCheck(
                label: "advanceToPersonalization.minimumDwellCompleted",
                frame: latestFrame
            )
            logCustomColorGuide(
                "advanceToPersonalization promotingToStep6 latestPersonalizationFrame=\(guideDebugFrameDescription(latestFrame)) " +
                "latestVisible=\(latestVisible)"
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                customColorPersonalizationGuideStep = .step6_personalizationExplanation
            }
            customColorPersonalizationScrollStepStartedAt = nil
        }
    }

    func isGuideTargetVisibleOnScreen(_ frame: CGRect) -> Bool {
        let visibleBounds = UIScreen.main.bounds.insetBy(dx: 0, dy: 120)
        return frame.width > 1 &&
        frame.height > 1 &&
        frame.maxY > visibleBounds.minY &&
        frame.minY < visibleBounds.maxY
    }

    func advanceWardrobeAddGuideToChooseOptionIfNeeded() {
        guard wardrobeAddGuideStep == .step1_clickAddButton else { return }
        guard let feature = guideManager.currentFeatureExperienceFeature else { return }
        guard wardrobeGuideStep2Target(for: feature) != nil else { return }

        guideManager.resetGuideTargetFrames([
            .wardrobeManualCreateEntry,
            .wardrobeBatchImportEntry,
            .wardrobeShortcutManualCreateAction,
            .wardrobeShortcutBatchImportAction
        ])

        withAnimation(.easeInOut(duration: 0.25)) {
            wardrobeAddGuideStep = .step2_chooseTargetOption
        }
    }

    func handleWidgetGuideReturnAction() {
        guard guideManager.currentFeatureExperienceFeature == .widgetCustomize else { return }
        guard widgetCustomizeStep == .step1_returnToMe else { return }

        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard guideManager.currentFeatureExperienceFeature == .widgetCustomize,
                  widgetCustomizeStep == .step1_returnToMe,
                  guideManager.lastKnownHomeTab == "me" else { return }
            advanceWidgetGuideFromReturnStep()
        }
    }

    func handleLocalFileBackupRestoreGuideReturnAction() {
        guard guideManager.currentFeatureExperienceFeature == .localFileBackupRestore else { return }
        guard localFileBackupRestoreGuideStep == .step1_returnToMe else { return }

        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard guideManager.currentFeatureExperienceFeature == .localFileBackupRestore,
                  localFileBackupRestoreGuideStep == .step1_returnToMe,
                  guideManager.lastKnownHomeTab == "me" else { return }
            advanceLocalFileBackupRestoreGuideFromReturnStep()
        }
    }

    func handleExportCSVGuideReturnAction() {
        guard guideManager.currentFeatureExperienceFeature == .exportCSV else { return }
        guard exportCSVGuideStep == .step1_returnToMe else { return }

        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard guideManager.currentFeatureExperienceFeature == .exportCSV,
                  exportCSVGuideStep == .step1_returnToMe,
                  guideManager.lastKnownHomeTab == "me" else { return }
            advanceExportCSVGuideFromReturnStep()
        }
    }

    func handleCloudFileBackupRestoreGuideReturnAction() {
        guard guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore else { return }
        guard cloudFileBackupRestoreGuideStep == .step1_returnToMe else { return }

        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard guideManager.currentFeatureExperienceFeature == .cloudFileBackupRestore,
                  cloudFileBackupRestoreGuideStep == .step1_returnToMe,
                  guideManager.lastKnownHomeTab == "me" else { return }
            advanceCloudFileBackupRestoreGuideFromReturnStep()
        }
    }

    func handleWealthMainTabChanged(_ tab: String) {
        guard guideManager.currentFeatureExperienceFeature == .wealth else { return }

        let targetStep: WealthGuideStep
        switch tab {
        case WealthMainTab.divination.rawValue:
            targetStep = .step3_divination
        case WealthMainTab.moneyCounting.rawValue:
            targetStep = .step4_moneyCounting
        case WealthMainTab.wealthStorage.rawValue:
            targetStep = .step5_wealthStorage
        default:
            return
        }

        guard targetStep.rawValue > wealthGuideStep.rawValue else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            wealthGuideStep = targetStep
        }
    }

    func usesPreUnlockWardrobeGuide(for feature: FeatureItem) -> Bool {
        guard isPreUnlockWardrobeGuideReusableFeature(feature) else { return false }

        // spaceBook 特殊处理：如果 ootd 已解锁，即使 spaceBook 未解锁也不走衣橱预引导
        // 因为 spaceBook 的解锁条件是"创建一个穿搭手账以及手账书页"，此时应引导用户去点击穿搭手帐入口
        if feature == .spaceBook {
            return !FeatureUnlockManager.shared.isUnlocked(.ootd)
        }

        return !FeatureUnlockManager.shared.isUnlocked(feature)
    }

    func acceptsManualCreateGuideCompletion(for feature: FeatureItem) -> Bool {
        guard let target = wardrobeGuideStep2Target(for: feature) else { return false }
        return target == .manualCreate || target == .either
    }

    func acceptsBatchImportGuideCompletion(for feature: FeatureItem) -> Bool {
        guard let target = wardrobeGuideStep2Target(for: feature) else { return false }
        return target == .batchImport || target == .either
    }

    var currentWardrobeGuideStep1Message: String {
        guard let feature = guideManager.currentFeatureExperienceFeature else {
            return "先点击衣橱右上角的 + 号，展开创建菜单。"
        }
        guard feature == .batchImport else {
            return "先点击衣橱右上角的 + 号，展开创建菜单。"
        }
        return FeatureUnlockManager.shared.isUnlocked(feature)
            ? "先点击右上角 + 号，展开菜单。"
            : "解锁前先点击右上角 + 号，展开菜单。"
    }

    var currentWardrobeGuideStep2Title: String {
        guard let feature = guideManager.currentFeatureExperienceFeature else { return "选择创建方式" }
        guard let target = wardrobeGuideStep2Target(for: feature) else {
            return "选择创建方式"
        }
        switch target {
        case .manualCreate:
            return "点击「手动创建」"
        case .batchImport:
            return "点击「批量导入」"
        case .either:
            return "选择创建方式"
        }
    }

    var currentWardrobeGuideStep2Message: String {
        guard let feature = guideManager.currentFeatureExperienceFeature else { return "在展开菜单中选择创建方式，继续完成任务。" }
        switch feature {
        case .ootd:
            return "在菜单里选择「手动创建」或「批量导入」任一方式，先把裙子准备好，后面就能解锁穿搭手帐。"
        case .ootdDefaultBook:
            return "在菜单里选择「手动创建」或「批量导入」任一方式，先准备几件裙子，魔法贴纸体验会更完整。"
        case .calendar:
            return "在菜单里选择「手动创建」或「批量导入」任一方式，先录入裙子，梦裙日历才会有内容。"
        case .spaceBook:
            return "在菜单里选择「手动创建」或「批量导入」任一方式，先补齐衣橱内容并解锁穿搭手帐，之后再继续空间手帐前置任务。"
        case .batchImport:
            if FeatureUnlockManager.shared.isUnlocked(feature) {
                return "现在点击「批量导入」，就能一次导入多件裙子。"
            } else {
                return "解锁前先点击「手动创建」，完成一次基础录入流程。"
            }
        default:
            return "在展开菜单中选择创建方式，继续完成任务。"
        }
    }

    func handleReturnToMeGuideAction() {
        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)
    }

    func handleAIAnalysisGuideReturnAction() {
        guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }
        guard aiAnalysisStep == .preUnlockStep1ReturnToMe else { return }

        didDismissAIAnalysisReturnStep = true
        NotificationCenter.default.post(name: .dismissMagicTasksView, object: nil)
    }

    func advanceAIAnalysisGuideFromReturnStepIfNeeded() {
        guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }
        guard aiAnalysisStep == .preUnlockStep1ReturnToMe else { return }
        guard didDismissAIAnalysisReturnStep else { return }
        guard currentTab == "me" || guideManager.lastKnownHomeTab == "me" else { return }
        guard guideManager.guideTargetFrame(for: .aiAnalysisVIPCard) != nil else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            aiAnalysisStep = .preUnlockStep2ClickVIP
        }
    }

    func resolvedAIAnalysisPostUnlockEntryStep() -> AIAnalysisGuideStep {
        let activeTab = currentTab == "wardrobe" ? guideManager.lastKnownHomeTab : currentTab
        guard activeTab == "petChat" else {
            return .postUnlockStep1ClickPetChatTab
        }

        return aiAnalysisRequiresPetAdoptionGuide
            ? .postUnlockStep2BrowsePets
            : .postUnlockStep5ClickSearchBar
    }

    func advanceAIAnalysisGuideAfterEnteringPetChatIfNeeded() {
        guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }
        guard aiAnalysisStep == .postUnlockStep1ClickPetChatTab else { return }
        guard currentTab == "petChat" else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            aiAnalysisStep = aiAnalysisRequiresPetAdoptionGuide
                ? .postUnlockStep2BrowsePets
                : .postUnlockStep5ClickSearchBar
        }
    }

    func handleAIAnalysisAdoptionSelectionChanged(_ petId: String) {
        guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }
        guard aiAnalysisRequiresPetAdoptionGuide else { return }

        if aiAnalysisStep == .postUnlockStep3AdoptNaicha,
           petId != PetCharacter.naicha.id {
            withAnimation(.easeInOut(duration: 0.3)) {
                aiAnalysisStep = .postUnlockStep2BrowsePets
            }
        }

        guard aiAnalysisStep == .postUnlockStep2BrowsePets else { return }

        if petId != PetCharacter.naicha.id {
            didBrowseAwayFromNaichaInAIAnalysisGuide = true
            return
        }

        guard didBrowseAwayFromNaichaInAIAnalysisGuide else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            aiAnalysisStep = .postUnlockStep3AdoptNaicha
        }
    }

    func returnToMeGuideContent(
        in geometry: GeometryProxy,
        title: String,
        message: String,
        currentStep: Int,
        totalSteps: Int,
        accent: Color,
        onReturn: @escaping () -> Void
    ) -> some View {
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

            CatPawTapAnimation(
                position: CGPoint(x: backButtonFrame.midX, y: backButtonFrame.midY),
                delay: 0.5
            )

            if guideManager.lastKnownHomeTab == "me" {
                Button {
                    onReturn()
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 72, height: 72)
                }
                .captureGuideInteractionRegion("feature.return.hotspot")
                .position(x: backButtonFrame.midX, y: backButtonFrame.midY)
            }

            VStack {
                Spacer()
                featureStepBubble(
                    title: title,
                    message: message,
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    accent: accent,
                    actionTitle: nil,
                    onSkip: { guideManager.dismissFeatureExperienceGuide() },
                    onAction: nil
                )
                .padding(.bottom, 120)
            }
        }
    }

    func highlightedRectGuideContent(
        frame: CGRect,
        cornerRadius: CGFloat,
        title: String,
        message: String,
        currentStep: Int,
        totalSteps: Int,
        accent: Color,
        actionTitle: String?,
        onAction: (() -> Void)?,
        bubbleOnTop: Bool = false,
        showPulse: Bool = true,
        catPawPosition: CGPoint? = nil,
        onHighlightTap: (() -> Void)? = nil
    ) -> some View {
        ZStack {
            ZStack {
                HollowMaskView(
                    highlightFrame: frame,
                    highlightType: .roundedRect,
                    cornerRadius: cornerRadius
                )

                RoundedRectHighlightView(
                    frame: frame,
                    cornerRadius: cornerRadius,
                    showPulse: showPulse
                )
            }
            .allowsHitTesting(false)

            // 高亮区域的透明点击层，用于在点击穿透的同时通知引导推进
            if let onHighlightTap = onHighlightTap {
                Color.clear
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onHighlightTap()
                    }
            }

            if let catPawPosition {
                CatPawTapAnimation(
                    position: catPawPosition,
                    delay: 0.5
                )
            }

            VStack {
                if bubbleOnTop {
                    featureStepBubble(
                        title: title,
                        message: message,
                        currentStep: currentStep,
                        totalSteps: totalSteps,
                        accent: accent,
                        actionTitle: actionTitle,
                        onSkip: { guideManager.dismissFeatureExperienceGuide() },
                        onAction: onAction
                    )
                    .padding(.top, 72)
                    .allowsHitTesting(true)
                    Spacer()
                        .allowsHitTesting(false)
                } else {
                    Spacer()
                        .allowsHitTesting(false)
                    featureStepBubble(
                        title: title,
                        message: message,
                        currentStep: currentStep,
                        totalSteps: totalSteps,
                        accent: accent,
                        actionTitle: actionTitle,
                        onSkip: { guideManager.dismissFeatureExperienceGuide() },
                        onAction: onAction
                    )
                    .padding(.bottom, 120)
                    .allowsHitTesting(true)
                }
            }
        }
    }

    func bottomBubbleGuideContent(
        title: String,
        message: String,
        currentStep: Int,
        totalSteps: Int,
        accent: Color,
        actionTitle: String,
        onAction: @escaping () -> Void
    ) -> some View {
        VStack {
            Spacer()
            featureStepBubble(
                title: title,
                message: message,
                currentStep: currentStep,
                totalSteps: totalSteps,
                accent: accent,
                actionTitle: actionTitle,
                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                onAction: onAction
            )
            .padding(.bottom, 120)
        }
    }

    func simpleFeatureCardGuide(
        icon: String,
        accent: Color,
        title: String,
        subtitle: String
    ) -> some View {
        VStack {
            Spacer()
            featureStepBubble(
                title: title,
                message: subtitle,
                currentStep: 1,
                totalSteps: 1,
                accent: accent,
                actionTitle: "知道了",
                onSkip: { guideManager.dismissFeatureExperienceGuide() },
                onAction: {
                    guideManager.completeFeatureExperienceGuide()
                }
            )
            .overlay(alignment: .top) {
                Image(systemName: icon)
                    .font(.system(size: 38))
                    .foregroundStyle(accent)
                    .offset(y: -26)
            }
            .padding(.bottom, 120)
        }
    }

    func genericGuideContent(for feature: FeatureItem) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: feature.icon)
                    .font(.system(size: 50))
                    .foregroundStyle(magicPalette.accent)

                Text(feature.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(magicPalette.primaryText)

                Text("探索这个神奇的功能")
                    .font(.subheadline)
                    .foregroundStyle(magicPalette.secondaryText)

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
            .padding(.bottom, 120)
        }
    }

    func featureStepBubble(
        title: String,
        message: String,
        currentStep: Int,
        totalSteps: Int,
        accent: Color,
        actionTitle: String?,
        actionGuideTarget: GuideTargetKey? = nil,
        onSkip: @escaping () -> Void,
        onAction: (() -> Void)?
    ) -> some View {
        GenericFeatureGuideBubbleView(
            title: title,
            message: message,
            currentStep: currentStep,
            totalSteps: totalSteps,
            accent: accent,
            actionTitle: actionTitle,
            actionGuideTarget: actionGuideTarget,
            onSkip: onSkip,
            onAction: onAction
        )
    }
}
#endif
