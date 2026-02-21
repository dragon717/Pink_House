//
//  DreamCalendarComponents.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI
import UIKit

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
            Color.clear
                .aspectRatio(1.0, contentMode: .fit)
                .overlay(
                    GeometryReader { geo in
                        let size = geo.size
                        ZStack {
                            // Background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color(uiColor: theme.accentColor).opacity(0.1) : Color.clear)
                            
                            // Content Layer
                            ZStack(alignment: .bottomTrailing) {
                                if let displayClothing = clothings.first(where: { shouldShowImage(for: $0) }),
                                   let firstImage = displayClothing.imagePaths.first {
                                    AsyncDownsampledImage(
                                        fileName: firstImage,
                                        targetSize: CGSize(width: 100, height: 100),
                                        content: { uiImage in
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: size.width, height: size.height)
                                                .clipped()
                                                .onAppear {
                                                    #if DEBUG
                                                    print("CalendarCell [\(CalendarHelper.shared.dayOfMonth(dateObj.date))]: Cell Size: \(size), Image Size: \(uiImage.size)")
                                                    #endif
                                                }
                                        },
                                        placeholder: {
                                            Color.gray.opacity(0.1)
                                        }
                                    )
                                    .frame(width: size.width, height: size.height)
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
                                        .frame(width: size.width, height: size.height)
                                    }
                                }
                                
                                // Status Label (Rendered only if NOT bottomTrailing, or handled separately)
                                if let statusInfo = getStatusInfo(), statusInfo.alignment != .bottomTrailing {
                                    Text(statusInfo.text)
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Color(uiColor: statusInfo.color))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                        .padding(2)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: statusInfo.alignment)
                                }
                                
                                // Day Number (Unified Position: Bottom Right)
                                let hasImage = !clothings.isEmpty && clothings.contains(where: { shouldShowImage(for: $0) })
                                HStack(spacing: 2) {
                                    // Inject Status Label here if alignment is bottomTrailing
                                    if let statusInfo = getStatusInfo(), statusInfo.alignment == .bottomTrailing {
                                        Text(statusInfo.text)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(Color(uiColor: statusInfo.color))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    
                                    Text("\(CalendarHelper.shared.dayOfMonth(dateObj.date))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(dateTextColor(hasImage: hasImage))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background {
                                            if hasImage {
                                                Capsule()
                                                    .fill(.regularMaterial)
                                                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                                            }
                                        }
                                        .shadow(color: .black.opacity(hasImage ? 0 : 0.3), radius: 1, x: 0, y: 0.5)
                                }
                                .padding(2)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dateObj.isCurrentMonth ? 1.0 : 0.3)
    }
    
    private func getStatusInfo() -> (text: String, color: UIColor, alignment: Alignment)? {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        
        // 1. Check for Deposit (Highest Priority)
        if clothings.contains(where: { isDepositDay($0, on: dateObj.date) }) {
            // Deposit is also a "Start" event, so we put it bottomTrailing
            return (isPad ? "定金" : "定", theme.depositColor, .bottomTrailing)
        }
        
        // 2. Check for Final Payment
        if let clothing = clothings.first(where: { isFinalPaymentStartOrEnd($0, on: dateObj.date) }) {
            // Check if it is start or end
            if let start = clothing.finalPaymentDate, Calendar.current.isDate(start, inSameDayAs: dateObj.date) {
                // Start -> Bottom Right
                return (isPad ? "尾款" : "尾", theme.finalPaymentColor, .bottomTrailing)
            } else {
                // End -> Bottom Left
                return (isPad ? "尾款" : "尾", theme.finalPaymentColor, .bottomLeading)
            }
        }
        
        return nil
    }
    
    private func shouldShowImage(for clothing: Clothing) -> Bool {
        // 1. Must have image
        guard !clothing.imagePaths.isEmpty else { return false }
        
        let date = dateObj.date
        let calendar = Calendar.current
        
        // 2. Deposit Day -> Show
        if let d = clothing.depositDate, calendar.isDate(d, inSameDayAs: date) { return true }
        
        // 3. Final Payment Start -> Show
        if let f = clothing.finalPaymentDate, calendar.isDate(f, inSameDayAs: date) { return true }
        
        // 4. Final Payment End -> Show
        if let e = clothing.finalPaymentEndDate, calendar.isDate(e, inSameDayAs: date) { return true }
        
        // 5. Otherwise (Middle days) -> Hide
        return false
    }
    
    private func dateTextColor(hasImage: Bool) -> Color {
        if dateObj.isToday {
            return Color(uiColor: theme.accentColor)
        } else if hasImage {
            return .primary // Use primary color on material background
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
        let calendar = Calendar.current
        if calendar.isDate(fDate, inSameDayAs: date) { return true }
        
        if let endDate = clothing.finalPaymentEndDate {
            let target = calendar.startOfDay(for: date)
            let start = calendar.startOfDay(for: fDate)
            let end = calendar.startOfDay(for: endDate)
            return target > start && target <= end
        }
        return false
    }
    
    private func isFinalPaymentStartOrEnd(_ clothing: Clothing, on date: Date) -> Bool {
        guard let start = clothing.finalPaymentDate else { return false }
        let calendar = Calendar.current
        
        // Check start
        if calendar.isDate(start, inSameDayAs: date) { return true }
        
        // Check end
        if let end = clothing.finalPaymentEndDate, calendar.isDate(end, inSameDayAs: date) { return true }
        
        return false
    }
}



struct CalendarEventRow: View {
    let clothing: Clothing
    let date: Date
    let theme: CalendarTheme
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GlassCard {
            HStack(spacing: 10) {
                // 1. Image
                if let imagePath = clothing.imagePaths.first {
                    AsyncDownsampledImage(
                        fileName: imagePath,
                        targetSize: CGSize(width: 50, height: 50),
                        content: { uiImage in
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        },
                        placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(Image(systemName: "tshirt").foregroundStyle(.secondary))
                        }
                    )
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(Image(systemName: "tshirt").foregroundStyle(.secondary))
                }
                
                // 2. Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(clothing.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        if let brand = clothing.brand {
                            Text(brand.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Event Status Label
                        if isDepositDay {
                            Text("定金日")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(uiColor: theme.depositColor).opacity(0.2))
                                .foregroundStyle(Color(uiColor: theme.depositColor))
                                .clipShape(Capsule())
                        } else if isFinalPaymentDay {
                            Text("预计尾款日")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(uiColor: theme.finalPaymentColor).opacity(0.2))
                                .foregroundStyle(Color(uiColor: theme.finalPaymentColor))
                                .clipShape(Capsule())
                        }
                    }
                }
                
                Spacer()
                
                // 3. Price Info
                VStack(alignment: .trailing, spacing: 2) {
                    if clothing.isDepositPlan {
                        Text("定金¥\(clothing.totalDeposit.formatted(.number.precision(.fractionLength(0))))")
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(Color(uiColor: theme.depositColor))
                        
                        Text("尾款¥\(clothing.totalBalance.formatted(.number.precision(.fractionLength(0))))")
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(Color(uiColor: theme.finalPaymentColor))
                    }
                }
            }
            .padding(10)
        }
    }
    
    private var isDepositDay: Bool {
        guard let d = clothing.depositDate else { return false }
        return Calendar.current.isDate(d, inSameDayAs: date)
    }
    
    private var isFinalPaymentDay: Bool {
        guard let f = clothing.finalPaymentDate else { return false }
        let calendar = Calendar.current
        if calendar.isDate(f, inSameDayAs: date) { return true }
        
        if let endDate = clothing.finalPaymentEndDate {
            let target = calendar.startOfDay(for: date)
            let start = calendar.startOfDay(for: f)
            let end = calendar.startOfDay(for: endDate)
            return target > start && target <= end
        }
        return false
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
        .background(Color.white.opacity(0.1))
    }
}

// MARK: - Popups
struct UnifiedEventsPopup: View {
    let title: String
    let clothings: [Clothing]
    var filterDate: Date? = nil // Optional: If set, only shows events for this specific date
    var onClose: () -> Void
    var onDayTap: ((Date) -> Void)? = nil // Optional drill-down
    
    @Environment(CalendarThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    // Group clothings by day
    private var groupedClothings: [(Date, [Clothing])] {
        let calendar = Calendar.current
        var events: [(Date, Clothing)] = []
        
        for clothing in clothings {
            // 1. Check Deposit Date
            if let d = clothing.depositDate {
                let date = calendar.startOfDay(for: d)
                // Filter logic
                if let filter = filterDate {
                    if calendar.isDate(date, inSameDayAs: filter) {
                        events.append((date, clothing))
                    }
                } else {
                    events.append((date, clothing))
                }
            }
            
            // 2. Check Final Payment Date Range
            if let f = clothing.finalPaymentDate {
                let start = calendar.startOfDay(for: f)
                let end = clothing.finalPaymentEndDate.map { calendar.startOfDay(for: $0) } ?? start
                
                // Determine the range of dates to check
                var datesToCheck: [Date] = []
                
                if let filter = filterDate {
                    // Optimization: Only check the filter date if it falls within range
                    let filterDay = calendar.startOfDay(for: filter)
                    if filterDay >= start && filterDay <= end {
                        datesToCheck.append(filterDay)
                    }
                } else {
                    // Add all dates in range
                    var d = start
                    while d <= end {
                        datesToCheck.append(d)
                        d = calendar.date(byAdding: .day, value: 1, to: d)!
                    }
                }
                
                for date in datesToCheck {
                    // Avoid duplicate if deposit and final payment are on the same day
                    // Only need to check if we are on the deposit day
                    if let d = clothing.depositDate, calendar.isDate(d, inSameDayAs: date) {
                        // Already processed in step 1 (Deposit check)
                        continue
                    }
                    events.append((date, clothing))
                }
            }
        }
        
        // Group by Date
        let groupedDict = Dictionary(grouping: events, by: { $0.0 })
        
        // Convert to [(Date, [Clothing])] and Sort
        // Remove duplicates within each day (same clothing might appear multiple times due to different event types)
        return groupedDict.map { (date, eventList) in
            var seenIDs = Set<UUID>()
            let uniqueClothings = eventList.compactMap { event -> Clothing? in
                let clothing = event.1
                if seenIDs.contains(clothing.id) {
                    return nil
                }
                seenIDs.insert(clothing.id)
                return clothing
            }
            return (date, uniqueClothings)
        }.sorted { $0.0 < $1.0 }
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
                .background(
                    colorScheme == .dark
                        ? Color(uiColor: .secondarySystemGroupedBackground).opacity(0.95)
                        : Color(uiColor: themeManager.currentTheme.backgroundColor).opacity(0.95)
                )
                
                Divider()
                
                if groupedClothings.isEmpty {
                    ContentUnavailableView("无安排", systemImage: "calendar.badge.exclamationmark")
                        .frame(height: 300)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(groupedClothings, id: \.0) { date, items in
                                VStack(alignment: .leading, spacing: 6) {
                                    // Date Header (Only show if we have multiple groups or if it's a month view context)
                                    // If we are in "Day View" (title is the date), showing it again is redundant?
                                    // Let's check if the title already contains the date string.
                                    if !title.contains(date.formatted(date: .complete, time: .omitted)) && 
                                       !title.contains(date.formatted(date: .abbreviated, time: .omitted)) {
                                        Text(date.formatted(date: .complete, time: .omitted))
                                            .font(.subheadline)
                                            .foregroundStyle(Color(uiColor: themeManager.currentTheme.accentColor))
                                            .padding(.horizontal)
                                    }
                                    
                                    // Items Grid
                                    LazyVStack(spacing: 8) {
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
                                                        CalendarEventRow(clothing: clothing, date: date, theme: themeManager.currentTheme)
                                                    }
                                                } else {
                                                    CalendarEventRow(clothing: clothing, date: date, theme: themeManager.currentTheme)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .padding(.vertical, 6)
                                .background(
                                    colorScheme == .dark
                                        ? Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.6)
                                        : Color.white.opacity(0.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 450)
                }
            }
            .background(
                colorScheme == .dark
                    ? Color(uiColor: .secondarySystemGroupedBackground).opacity(0.95)
                    : Color(uiColor: themeManager.currentTheme.backgroundColor).opacity(0.95)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(20)
        }
    }
}
