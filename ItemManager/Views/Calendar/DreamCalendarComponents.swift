//
//  DreamCalendarComponents.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI

// MARK: - Models
enum CalendarViewMode: String, CaseIterable, Identifiable {
    case recent = "最近"
    case monthly = "月度"
    case yearly = "年度"
    
    var id: String { rawValue }
}

// MARK: - Cells
struct DreamCalendarCell: View {
    let dateObj: CalendarDate
    let clothings: [Clothing] // Events for this day
    let isSelected: Bool
    let theme: CalendarTheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color(uiColor: theme.accentColor).opacity(0.1) : Color.clear)
                
                // Force Square Aspect Ratio container
                Color.clear
                    .aspectRatio(1.0, contentMode: .fit)
                
                // Content Layer
                GeometryReader { geo in
                    ZStack(alignment: .bottomTrailing) {
                        if let firstImage = clothings.first(where: { !$0.imagePaths.isEmpty })?.imagePaths.first,
                           let uiImage = ImageManager.shared.loadImage(fileName: firstImage) {
                            
                            // Image Mode: Full cell image
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.5), lineWidth: 1))
                            
                            // Count Badge if > 1
                            if clothings.count > 1 {
                                Text("\(clothings.count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(Color(uiColor: theme.accentColor))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                                    .position(x: 10, y: 10) // Top left corner relative to cell
                            }
                            
                        } else {
                            // Standard Mode: No image
                            // Visual Indicators (Dots) centered
                            if !clothings.isEmpty {
                                ZStack {
                                    eventVisualFallback
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        
                        // Day Number (Unified Position: Bottom Right)
                        let hasImage = !clothings.isEmpty && clothings.contains(where: { !$0.imagePaths.isEmpty })
                        Text("\(CalendarHelper.shared.dayOfMonth(dateObj.date))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(dateTextColor(hasImage: hasImage))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                if hasImage {
                                    Capsule()
                                        .fill(.regularMaterial)
                                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                                }
                            }
                            .shadow(color: .black.opacity(hasImage ? 0 : 0.3), radius: 1, x: 0, y: 0.5)
                            .padding(2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dateObj.isCurrentMonth ? 1.0 : 0.3)
    }
    
    private func dateTextColor(hasImage: Bool) -> Color {
        if hasImage {
            return .primary // Use primary color on material background
        } else if dateObj.isToday {
            return Color(uiColor: theme.accentColor)
        } else {
            return .primary
        }
    }
    
    @ViewBuilder
    private var eventVisualFallback: some View {
        HStack(spacing: 3) {
            ForEach(clothings.prefix(3)) { clothing in
                let isDeposit = isDepositDay(clothing, on: dateObj.date)
                let isFinal = isFinalPaymentDay(clothing, on: dateObj.date)
                
                if isDeposit {
                    Circle()
                        .fill(Color(uiColor: theme.depositColor))
                        .frame(width: 5, height: 5)
                } else if isFinal {
                    Circle()
                        .fill(Color(uiColor: theme.finalPaymentColor))
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .fill(Color(uiColor: theme.accentColor))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
    
    private func isDepositDay(_ clothing: Clothing, on date: Date) -> Bool {
        guard let dDate = clothing.depositDate else { return false }
        return Calendar.current.isDate(dDate, inSameDayAs: date)
    }
    
    private func isFinalPaymentDay(_ clothing: Clothing, on date: Date) -> Bool {
        guard let fDate = clothing.finalPaymentDate else { return false }
        return Calendar.current.isDate(fDate, inSameDayAs: date)
    }
}



struct ClothingCardMonthly: View {
    let clothing: Clothing
    let date: Date
    let theme: CalendarTheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Large Image
            if let imagePath = clothing.imagePaths.first, let uiImage = ImageManager.shared.loadImage(fileName: imagePath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .aspectRatio(1.0, contentMode: .fit)
                    .overlay(Image(systemName: "tshirt").font(.largeTitle).foregroundStyle(.secondary))
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(clothing.name)
                    .font(.caption)
                    .bold()
                    .lineLimit(1)
                
                HStack {
                    if let depositDate = clothing.depositDate, Calendar.current.isDate(depositDate, inSameDayAs: date) {
                        Text("定金")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: theme.depositColor).opacity(0.2))
                            .foregroundStyle(Color(uiColor: theme.depositColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else if let finalDate = clothing.finalPaymentDate, Calendar.current.isDate(finalDate, inSameDayAs: date) {
                        Text("尾款")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: theme.finalPaymentColor).opacity(0.2))
                            .foregroundStyle(Color(uiColor: theme.finalPaymentColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

struct WeekHeaderView: View {
    let theme: CalendarTheme
    let weeks = ["日", "一", "二", "三", "四", "五", "六"]
    
    var body: some View {
        HStack {
            ForEach(weeks, id: \.self) { week in
                Text(week)
                    .font(.custom(theme.fontName, size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground).opacity(0.5))
    }
}

// MARK: - Popups
struct UnifiedEventsPopup: View {
    let title: String
    let clothings: [Clothing]
    var onClose: () -> Void
    var onDayTap: ((Date) -> Void)? = nil // Optional drill-down
    
    @Environment(CalendarThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    // Group clothings by day
    private var groupedClothings: [(Date, [Clothing])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: clothings) { clothing -> Date in
            // Try to group by deposit date first, then final payment date
            // This is a heuristic; if a clothing has both, it might appear in one.
            // For a single day view, they will all be on the same day.
            // For a month view, we want to place them on the relevant day in that month.
            
            // Check if deposit date is relevant (e.g. if we are showing a month, is it in this month?)
            // Since we don't pass the "context date" here easily for filtering, we assume 'clothings' is already filtered.
            // We just need to find WHICH date it belongs to.
            
            if let d = clothing.depositDate {
                return calendar.startOfDay(for: d)
            }
            if let f = clothing.finalPaymentDate {
                return calendar.startOfDay(for: f)
            }
            return calendar.startOfDay(for: Date())
        }
        return grouped.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(title)
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                    
                    Spacer()
                    
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(colorScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : Color.white)
                
                Divider()
                
                if groupedClothings.isEmpty {
                    ContentUnavailableView("无安排", systemImage: "calendar.badge.exclamationmark")
                        .frame(height: 300)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(groupedClothings, id: \.0) { date, items in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Date Header (Only show if we have multiple groups or if it's a month view context)
                                    // If we are in "Day View" (title is the date), showing it again is redundant?
                                    // Let's check if the title already contains the date string.
                                    if !title.contains(date.formatted(date: .complete, time: .omitted)) && 
                                       !title.contains(date.formatted(date: .abbreviated, time: .omitted)) {
                                        Text(date.formatted(date: .complete, time: .omitted))
                                            .font(.headline)
                                            .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                                            .padding(.horizontal)
                                    }
                                    
                                    // Items Grid
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                                        ForEach(items) { clothing in
                                            Button {
                                                // If we have a drill-down action (e.g. Month -> Day), use it.
                                                // Otherwise, maybe go to detail?
                                                if let onDayTap = onDayTap {
                                                    onDayTap(date)
                                                }
                                            } label: {
                                                // Link to detail view directly if no drill-down
                                                if onDayTap == nil {
                                                    NavigationLink(destination: ClothingDetailView(clothing: clothing)) {
                                                        ClothingCardMonthly(clothing: clothing, date: date, theme: themeManager.currentTheme)
                                                    }
                                                } else {
                                                    ClothingCardMonthly(clothing: clothing, date: date, theme: themeManager.currentTheme)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .padding(.vertical, 8)
                                .background(colorScheme == .dark ? Color(uiColor: .tertiarySystemGroupedBackground) : Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .frame(maxHeight: 500)
                }
            }
            .background(colorScheme == .dark ? Color(uiColor: .systemGroupedBackground) : Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(20)
        }
    }
}
