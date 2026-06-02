//
//  DreamDressCalendarView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/10/26.
//

import SwiftUI
import SwiftData
import UIKit

struct DreamDressCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CalendarThemeManager.self) private var themeManager
    @Environment(ThemeManager.self) private var appThemeManager

    // Data Query
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothings: [Clothing]

    // AppStorage for persisting filter preference
    // 首次使用默认为 true，之后完全记录用户的选择习惯
    @AppStorage("calendarShowDepositPlanOnly") private var showDepositPlanOnly: Bool = true

    // State
    @State private var viewMode: CalendarViewMode = .monthly
    @State private var currentDate = Date() // Anchor date for Month/Year view
    @State private var showingDayPopup: Date? // Date for the popup
    @State private var showingMonthPreview: Date? // Month for the large preview popup
    @State private var viewModel = CalendarViewModel()
    @State private var showingThemeSelector = false // 主题选择器

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LiquidBackground(themeSkinWallpaperContext: .journal)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 1. Header with Mode Switcher
                    // iOS 18+: 页签选择器都在导航栏的 principal 位置显示

                    // 2. Main Content
                    TabView(selection: $viewMode) {
                        RecentTimelineView(viewModel: viewModel, onDayTap: { date in showingDayPopup = date })
                            .tag(CalendarViewMode.recent)

                        DualMonthScrollView(anchorDate: $currentDate, viewModel: viewModel, onDayTap: { date in showingDayPopup = date })
                            .tag(CalendarViewMode.monthly)

                        YearlyHeatmapView(
                            currentDate: $currentDate,
                            viewModel: viewModel,
                            onMonthTap: { monthDate in showingMonthPreview = monthDate }
                        )
                        .tag(CalendarViewMode.yearly)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: viewMode)
                }

                // 3. Popup Overlay (Day & Month)
                if let date = showingDayPopup {
                    UnifiedEventsPopup(
                        title: CalendarHelper.shared.completeDateString(date),
                        clothings: viewModel.clothings(for: date),
                        filterDate: date, // Pass context date to filter irrelevant events
                        onClose: { showingDayPopup = nil }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }

                if let monthDate = showingMonthPreview {
                    UnifiedEventsPopup(
                        title: CalendarHelper.shared.monthYearString(monthDate),
                        clothings: viewModel.clothings(forMonth: monthDate),
                        onClose: { showingMonthPreview = nil },
                        onDayTap: { date in
                            showingMonthPreview = nil
                            showingDayPopup = date
                        }
                    )
                    .transition(.opacity)
                    .zIndex(110)
                }
            }
            .applyNavigationConfig(
                viewMode: $viewMode,
                showFilter: $showDepositPlanOnly,
                themeManager: themeManager,
                onThemeTap: { showingThemeSelector = true }
            )
            .task {
                await updateData()
                // 初始化时检查是否需要应用客制化配色
                if themeManager.useCustomColorScheme {
                    themeManager.setCustomTheme(from: appThemeManager, colorScheme: colorScheme)
                }
            }
            .onAppear {
                NotificationCenter.default.post(name: .dreamDressCalendarOpened, object: nil)
            }
            .onChange(of: allClothings) { _, _ in
                Task { await updateData() }
            }
            .onChange(of: showDepositPlanOnly) { _, _ in
                Task { await updateData() }
            }
            .onChange(of: colorScheme) { _, _ in
                // 当系统颜色模式改变时，刷新主题
                themeManager.refreshTheme(from: appThemeManager, colorScheme: colorScheme)
            }
            .sheet(isPresented: $showingThemeSelector) {
                CalendarThemeSelectorView()
            }
        }
    }
    
    @MainActor
    private func updateData() async {
        let filtered = showDepositPlanOnly ? allClothings.filter { $0.isFinalPaymentPlan } : allClothings
        await viewModel.processClothings(filtered)
    }
    
    // MARK: - Legacy Header for < iOS 26
    // 在iOS 18-25下，导航栏显示返回按钮和筛选按钮，这里只显示模式选择器
    private var headerView: some View {
        HStack {
            Spacer()

            // Custom Segmented Control for older versions
            HStack(spacing: 0) {
                ForEach(CalendarViewMode.allCases) { mode in
                    Text(mode.displayName)
                        .font(.custom(themeManager.currentTheme.fontName, size: 14))
                        .fontWeight(viewMode == mode ? .bold : .regular)
                        .themeSkinLegibleText(level: .inline, slot: .segmentedControl)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(viewMode == mode ? Color(uiColor: themeManager.currentTheme.accentColor) : Color.clear)
                        .foregroundStyle(viewMode == mode ? .white : Color(uiColor: themeManager.currentTheme.accentColor))
                        .clipShape(Capsule())
                        .onTapGesture {
                            withAnimation {
                                viewMode = mode
                            }
                        }
                }
            }
            .padding(4)
            .background(Color(uiColor: themeManager.currentTheme.accentColor).opacity(0.1))
            .clipShape(Capsule())

            Spacer()
        }
        // 减少顶部padding，让页签更靠近导航栏
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Navigation Config Helper
// 返回按钮现在由外部包装视图通过 .toolbar 添加，不再通过参数传入
extension View {
    @ViewBuilder
    func applyNavigationConfig(
        viewMode: Binding<CalendarViewMode>,
        showFilter: Binding<Bool>,
        themeManager: CalendarThemeManager,
        onThemeTap: (() -> Void)? = nil
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .navigationBarHidden(false)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("视图模式".appLocalized, selection: viewMode) {
                            ForEach(CalendarViewMode.allCases) { mode in
                                Text(mode.displayName)
                                    .themeSkinLegibleText(level: .inline, slot: .segmentedControl)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            // 主题切换按钮
                            Button {
                                onThemeTap?()
                            } label: {
                                Image(systemName: "paintpalette")
                                    .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                            }

                            // 筛选按钮
                            Menu {
                                Toggle(isOn: Binding(
                                    get: { showFilter.wrappedValue },
                                    set: { newValue in
                                        withAnimation {
                                            showFilter.wrappedValue = newValue
                                        }
                                    }
                                )) {
                                    Label("只看心愿尾款".appLocalized, systemImage: "star")
                                }
                            } label: {
                                Image(systemName: showFilter.wrappedValue ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                            }
                        }
                    }
                }
        } else {
            // iOS 18-25: 显示导航栏，添加页签选择器和筛选按钮
            // 返回按钮由外部包装视图通过 .toolbar 添加
            self
                .navigationBarHidden(false)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // 页签选择器（中间）
                    ToolbarItem(placement: .principal) {
                        Picker("视图模式".appLocalized, selection: viewMode) {
                            ForEach(CalendarViewMode.allCases) { mode in
                                Text(mode.displayName)
                                    .themeSkinLegibleText(level: .inline, slot: .segmentedControl)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }

                    // 筛选按钮和主题按钮
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            // 主题切换按钮
                            Button {
                                onThemeTap?()
                            } label: {
                                Image(systemName: "paintpalette")
                                    .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                            }

                            // 筛选按钮
                            Menu {
                                Toggle(isOn: Binding(
                                    get: { showFilter.wrappedValue },
                                    set: { newValue in
                                        withAnimation {
                                            showFilter.wrappedValue = newValue
                                        }
                                    }
                                )) {
                                    Label("只看心愿尾款".appLocalized, systemImage: "star")
                                }
                            } label: {
                                Image(systemName: showFilter.wrappedValue ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                            }
                        }
                    }
                }
        }
    }
}

// MARK: - 1. Recent View (Yesterday / Today / Tomorrow)
struct RecentTimelineView: View {
    let viewModel: CalendarViewModel
    let onDayTap: (Date) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CalendarThemeManager.self) private var themeManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                daySection(offset: -1, title: "昨天")
                daySection(offset: 0, title: "今天")
                daySection(offset: 1, title: "明天")
                
                // Future Lookahead (Next 7 days)
                Text("未来一周".appLocalized)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top)
                
                ForEach(2...7, id: \.self) { offset in
                    if let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) {
                        let events = viewModel.clothings(for: date)
                        if !events.isEmpty {
                            CompactDayRow(date: date, clothings: events, theme: themeManager.currentTheme) {
                                onDayTap(date)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func daySection(offset: Int, title: String) -> some View {
        if let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title.appLocalized)
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    
                    Text(CalendarHelper.shared.abbreviatedDateString(date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    
                    Spacer()
                }
                
                let events = viewModel.clothings(for: date)
                if events.isEmpty {
                    Text("无特殊安排".appLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .themeSkinLegibleText(level: .inline, slot: .emptyState)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(events) { clothing in
                                ClothingCardTiny(clothing: clothing, date: date, theme: themeManager.currentTheme)
                                    .onTapGesture {
                                        onDayTap(date)
                                    }
                            }
                        }
                    }
                }
            }
            .padding()
            .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 16) {
                colorScheme == .dark
                    ? Color(uiColor: .secondarySystemGroupedBackground).opacity(0.8)
                    : Color(uiColor: themeManager.currentTheme.backgroundColor).opacity(0.9)
            }
        }
    }
}

struct ClothingCardTiny: View {
    let clothing: Clothing
    let date: Date
    let theme: CalendarTheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imagePath = clothing.imagePaths.first {
                AsyncDownsampledImage(
                    fileName: imagePath,
                    targetSize: CGSize(width: 80, height: 80),
                    content: { uiImage in
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipped()
                    },
                    placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 80, height: 80)
                            .overlay(Image(systemName: "tshirt").foregroundStyle(.secondary))
                    }
                )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .overlay(Image(systemName: "tshirt").foregroundStyle(.secondary))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(clothing.name)
                    .font(.caption)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    .lineLimit(1)
                
                HStack(spacing: 2) {
                    if let depositDate = clothing.depositDate, Calendar.current.isDate(depositDate, inSameDayAs: date) {
                        Circle().fill(Color(uiColor: theme.depositColor)).frame(width: 6, height: 6)
                        Text("定金".appLocalized).font(.caption2).foregroundStyle(.secondary)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    } else if let finalDate = clothing.finalPaymentDate, Calendar.current.isDate(finalDate, inSameDayAs: date) {
                        Circle().fill(Color(uiColor: theme.finalPaymentColor)).frame(width: 6, height: 6)
                        Text("尾款".appLocalized).font(.caption2).foregroundStyle(.secondary)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    }
                }
            }
            .padding(6)
            .frame(width: 80)
            .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 8, showsDecoration: false) {
                Color.white.opacity(0.7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 1)
    }
}

struct CompactDayRow: View {
    let date: Date
    let clothings: [Clothing]
    let theme: CalendarTheme
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(CalendarHelper.shared.abbreviatedDateString(date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    .frame(width: 80, alignment: .leading)
                
                // Visual indicators
                HStack(spacing: -8) {
                    ForEach(clothings.prefix(5)) { clothing in
                        if let imagePath = clothing.imagePaths.first {
                            AsyncDownsampledImage(
                                fileName: imagePath,
                                targetSize: CGSize(width: 30, height: 30),
                                content: { uiImage in
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 30, height: 30)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                                },
                                placeholder: {
                                    Circle()
                                        .fill(Color(uiColor: theme.accentColor))
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                                        .overlay(Text(clothing.name.prefix(1)).font(.caption2).foregroundStyle(.white))
                                }
                            )
                        } else {
                            Circle()
                                .fill(Color(uiColor: theme.accentColor))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                                .overlay(Text(clothing.name.prefix(1)).font(.caption2).foregroundStyle(.white))
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 12, showsDecoration: false) {
                Color(uiColor: theme.backgroundColor).opacity(0.9)
            }
        }
        .buttonStyle(.plain)
    }
}


// MARK: - 2. Monthly View (Dual Month Scroll)
struct DualMonthScrollView: View {
    @Binding var anchorDate: Date
    let viewModel: CalendarViewModel
    let onDayTap: (Date) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CalendarThemeManager.self) private var themeManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current Month
                monthSection(for: anchorDate)
                
                // Next Month
                if let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: anchorDate) {
                    monthSection(for: nextMonth)
                }
            }
            .padding(.bottom, 40)
        }
    }
    
    @ViewBuilder
    private func monthSection(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CalendarHelper.shared.monthYearString(date))
                .font(.custom(themeManager.currentTheme.fontName, size: 20))
                .bold()
                .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                .padding(.horizontal)
                .padding(.top)
            
            WeekHeaderView(theme: themeManager.currentTheme)
                .padding(.horizontal)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(CalendarHelper.shared.generateDates(for: date)) { dateObj in
                    DreamCalendarCell(
                        dateObj: dateObj,
                        clothings: viewModel.clothings(for: dateObj.date),
                        isSelected: false,
                        theme: themeManager.currentTheme
                    ) {
                        onDayTap(dateObj.date)
                    }
                    .aspectRatio(1.0, contentMode: .fit) // 强制正方形
                }
            }
            .padding(.horizontal)
        }
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 20) {
            colorScheme == .dark
                ? Color(uiColor: .secondarySystemGroupedBackground).opacity(0.8)
                : Color(uiColor: themeManager.currentTheme.backgroundColor).opacity(0.85)
        }
        .padding(.horizontal)
    }
}

// MARK: - 3. Yearly View (Heatmap)
struct YearlyHeatmapView: View {
    @Binding var currentDate: Date
    let viewModel: CalendarViewModel
    let onMonthTap: (Date) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CalendarThemeManager.self) private var themeManager
    
    private var year: Int {
        Calendar.current.component(.year, from: currentDate)
    }
    
    let months = 1...12
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]
    
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Button {
                        withAnimation {
                            currentDate = Calendar.current.date(byAdding: .year, value: -1, to: currentDate) ?? currentDate
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                            .padding()
                    }
                    
                    Text("%d年 概览".appLocalized(year))
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                    
                    Button {
                        withAnimation {
                            currentDate = Calendar.current.date(byAdding: .year, value: 1, to: currentDate) ?? currentDate
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                            .padding()
                    }
                }
                .padding(.top)
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(months, id: \.self) { month in
                        Button {
                            if let monthDate = Calendar.current.date(from: DateComponents(year: year, month: month)) {
                                onMonthTap(monthDate)
                            }
                        } label: {
                            VStack {
                                Text(CalendarHelper.shared.monthName(month, year: year))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                
                                Spacer()
                                
                                // Mini Heatmap Grid
                                if let monthDate = Calendar.current.date(from: DateComponents(year: year, month: month)) {
                                    MiniMonthGrid(monthDate: monthDate, viewModel: viewModel, theme: themeManager.currentTheme)
                                        .frame(maxWidth: .infinity)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1.0, contentMode: .fit)
                            .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 12, showsDecoration: false) {
                                colorScheme == .dark
                                    ? Color(uiColor: .secondarySystemGroupedBackground).opacity(0.8)
                                    : Color(uiColor: themeManager.currentTheme.backgroundColor).opacity(0.85)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}

struct MiniMonthGrid: View {
    let monthDate: Date
    let viewModel: CalendarViewModel
    let theme: CalendarTheme
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let days = CalendarHelper.shared.daysInMonth(monthDate)
        let cols = Array(repeating: GridItem(.fixed(6), spacing: 2), count: 7)
        
        LazyVGrid(columns: cols, spacing: 2) {
            // Empty prefix
            let firstDay = CalendarHelper.shared.firstOfMonth(monthDate)
            let weekday = CalendarHelper.shared.weekDay(firstDay)
            ForEach(0..<weekday, id: \.self) { _ in
                Color.clear.frame(width: 6, height: 6)
            }
            
            ForEach(1...days, id: \.self) { day in
                if let date = Calendar.current.date(byAdding: .day, value: day - 1, to: firstDay) {
                    let intensity = heatIntensity(for: date)
                    Circle()
                        .fill(intensityColor(intensity))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
    
    private func heatIntensity(for date: Date) -> Double {
        let count = viewModel.clothings(for: date).count
        return min(Double(count) / 3.0, 1.0) // Max intensity at 3 items
    }
    
    private func intensityColor(_ intensity: Double) -> Color {
        if intensity == 0 {
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1)
        }
        let baseColor = Color(uiColor: theme.accentColor)
        // 在黑暗模式下，让颜色更亮一点
        return baseColor.opacity(colorScheme == .dark ? (0.3 + intensity * 0.7) : (0.2 + intensity * 0.8))
    }
}

// MARK: - 日历主题选择器
struct CalendarThemeSelectorView: View {
    @Environment(CalendarThemeManager.self) private var themeManager
    @Environment(ThemeManager.self) private var appThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 预设主题区域（4个梦群日历主题）
                    presetThemesSection

                    // 客制化配色区域（第5个选项 + 用户自定义方案）
                    customColorSection
                }
                .padding()
            }
            .background(LiquidBackground(themeSkinWallpaperContext: .journal))
            .navigationTitle("选择主题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - 预设主题区域
    private var presetThemesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("预设主题")
                .font(.headline)
                .padding(.horizontal, 4)

            // 4个梦群日历主题
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(CustomColorPresets.all) { preset in
                    CalendarThemeButton(
                        preset: preset,
                        isSelected: themeManager.currentTheme.id == preset.id && !themeManager.useCustomColorScheme
                    ) {
                        themeManager.setPresetTheme(preset, colorScheme: colorScheme)
                        // 同步更新 ThemeManager 的选中预设
                        var newConfig = appThemeManager.themeColorConfig
                        newConfig.customColorConfig.selectedPresetId = preset.id
                        appThemeManager.themeColorConfig = newConfig
                    }
                }
            }
        }
    }

    // MARK: - 客制化配色区域
    private var customColorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("客制化配色")
                .font(.headline)
                .padding(.horizontal, 4)

            // 当前自定义配置
            Button {
                themeManager.setCustomTheme(from: appThemeManager, colorScheme: colorScheme)
            } label: {
                HStack(spacing: 16) {
                    // 预览色块 - 显示当前客制化配色
                    HStack(spacing: 4) {
                        let isDark = colorScheme == .dark
                        let customTheme = appThemeManager.themeColorConfig.customColorConfig.currentCustom
                        let textColors = [
                            isDark ? customTheme.darkTextPrimaryRGBA.color : customTheme.textPrimaryRGBA.color,
                            isDark ? customTheme.darkTextSecondaryRGBA.color : customTheme.textSecondaryRGBA.color,
                            isDark ? customTheme.darkTextAccentRGBA.color : customTheme.textAccentRGBA.color
                        ]
                        let cardColors = isDark ? customTheme.darkCardConfig : customTheme.cardConfig

                        // 字体配色
                        ForEach(textColors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 20, height: 20)
                        }

                        // 卡片背景
                        RoundedRectangle(cornerRadius: 4)
                            .fill(cardColors.backgroundRGBA.color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("自定义")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("自定义字体和卡片配色")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if themeManager.useCustomColorScheme && appThemeManager.themeColorConfig.customColorConfig.selectedPresetId == nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.pink)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(themeManager.useCustomColorScheme && appThemeManager.themeColorConfig.customColorConfig.selectedPresetId == nil ? Color.pink : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)

            // 用户保存的自定义方案
            if !appThemeManager.themeColorConfig.customColorConfig.userCustomThemes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("我的方案")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(appThemeManager.themeColorConfig.customColorConfig.userCustomThemes) { theme in
                        let preset = theme.toThemePreset()
                        Button {
                            themeManager.setPresetTheme(preset, colorScheme: colorScheme)
                            var newConfig = appThemeManager.themeColorConfig
                            newConfig.customColorConfig.selectedPresetId = nil
                            newConfig.customColorConfig.currentCustom = theme
                            appThemeManager.themeColorConfig = newConfig
                        } label: {
                            HStack(spacing: 12) {
                                // 预览色块
                                HStack(spacing: 4) {
                                    let isDark = colorScheme == .dark
                                    let textColors = [
                                        isDark ? theme.darkTextPrimaryRGBA.color : theme.textPrimaryRGBA.color,
                                        isDark ? theme.darkTextAccentRGBA.color : theme.textAccentRGBA.color
                                    ]
                                    let cardColors = isDark ? theme.darkCardConfig : theme.cardConfig

                                    ForEach(textColors, id: \.self) { color in
                                        Circle()
                                            .fill(color)
                                            .frame(width: 16, height: 16)
                                    }

                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(cardColors.backgroundRGBA.color)
                                        .frame(width: 16, height: 16)
                                }

                                Text(theme.name)
                                    .font(.subheadline)

                                Spacer()

                                if themeManager.currentTheme.id == theme.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.pink)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 跳转到配色设置页面的链接
            NavigationLink {
                MagicColorSettingsView()
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("调整配色方案")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }
        }
    }
}

// MARK: - 日历主题按钮
struct CalendarThemeButton: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // 预览卡片 - 显示完整的主题色（字体+卡片）
                RoundedRectangle(cornerRadius: 12)
                    .fill(preset.cardColors(forDarkMode: colorScheme == .dark).backgroundRGBA.color)
                    .frame(height: 60)
                    .overlay(
                        HStack(spacing: 4) {
                            let textColors = preset.textColors(forDarkMode: colorScheme == .dark)
                            // 字体配色预览
                            Circle().fill(textColors.primary.color).frame(width: 8, height: 8)
                            Circle().fill(textColors.secondary.color).frame(width: 8, height: 8)
                            Circle().fill(textColors.accent.color).frame(width: 8, height: 8)
                            Spacer()
                            // 定金/尾款色预览
                            Circle()
                                .fill(preset.cardColors(forDarkMode: colorScheme == .dark).depositRGBA.color)
                                .frame(width: 6, height: 6)
                            Circle()
                                .fill(preset.cardColors(forDarkMode: colorScheme == .dark).finalPaymentRGBA.color)
                                .frame(width: 6, height: 6)
                        }
                        .padding(8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 2)
                    )

                Text(preset.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
