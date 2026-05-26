//
//  DepositItemRow.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData

private func depositLocalizedDateString(_ date: Date, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = LanguageManager.shared.locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}

struct DepositItemRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    let clothing: Clothing
    @State private var showEditNoteAlert: Bool = false
    @State private var editingNote: String = ""
    @State private var thumbnailImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                // Top Section: Image + Basic Info
                HStack(alignment: .center, spacing: 12) {
                    // Image
                    if let uiImage = thumbnailImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        CutePlaceholderView(iconSize: 24)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .task {
                                if let imagePath = clothing.imagePaths.first {
                                    let size = CGSize(width: 80, height: 80)
                                    if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                                        self.thumbnailImage = cached
                                        return
                                    }
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                    if Task.isCancelled { return }
                                    self.thumbnailImage = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size)
                                }
                            }
                    }

                    // Basic Info
                    VStack(alignment: .leading, spacing: 6) {
                        Text(clothing.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(themeManager.primaryTextColor)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)

                        if let brand = clothing.brand {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill") // Placeholder icon
                                    .font(.caption2)
                                Text(brand.name)
                                    .font(.caption)
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            }
                            .foregroundStyle(themeManager.secondaryTextColor)
                        }

                        if clothing.stock > 1 {
                            Text("库存: %d".appLocalized(clothing.stock))
                                .font(.caption)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        }

                        // Tags
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(clothing.types.split(separator: ","), id: \.self) { type in
                                    TagView(text: String(type))
                                }
                                ForEach(clothing.sizes.split(separator: ","), id: \.self) { size in
                                    TagView(text: String(size))
                                }
                                ForEach(clothing.colors.split(separator: ","), id: \.self) { color in
                                    TagView(text: String(color))
                                }
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if clothing.isFullPaymentReservation {
                            Text("全款预约".appLocalized)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                                .themeSkinLegibleText(level: .chip, slot: .discountBadge)
                            Text("¥\(clothing.fullPaymentReservationTotalAmount.formatted(.number.precision(.fractionLength(0))))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                                .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                        } else {
                            Text("定金¥%@".appLocalized(clothing.totalDeposit.formatted(.number.precision(.fractionLength(0)))))
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                                .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                            Text("尾款¥%@".appLocalized(clothing.totalBalance.formatted(.number.precision(.fractionLength(0)))))
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                                .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                        }
                    }
                }

                Divider()

                VStack(spacing: 12) {
                    if clothing.isFullPaymentReservation {
                        TimelineRow(title: "全款预约", date: clothing.depositDate, trailing: getFullPaymentReservationStatus())
                    } else {
                        // Phase 1: Deposit (Always shown)
                        TimelineRow(title: "定金", date: clothing.depositDate, trailing: getDepositStatus())

                        // Phase 2: Final Payment
                        TimelineRow(title: "尾款", date: clothing.finalPaymentDate, trailing: getFinalPaymentStatus())
                    }
                }


                // Note Section
                if !clothing.note.isEmpty {
                    Text("备注: %@".appLocalized(clothing.note))
                        .font(.caption)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        .padding(8)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Footer
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.orange)
                    Text(clothing.isFullPaymentReservation ? "全款预约日期: %@".appLocalized(formatDate(clothing.depositDate)) : "预估尾款时间: %@".appLocalized(formatDate(clothing.finalPaymentDate)))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)

                    Spacer()

                    Button {
                        editingNote = clothing.note
                        showEditNoteAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                            Text("修改备注".appLocalized)
                                .themeSkinLegibleText(level: .chip, slot: .primaryButton)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "5D4037"))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .alert("修改备注".appLocalized, isPresented: $showEditNoteAlert) {
                        TextField("请输入备注".appLocalized, text: $editingNote)
                        Button("取消".appLocalized, role: .cancel) { }
                        Button("保存".appLocalized) {
                            saveNoteChange()
                        }
                    }
                }
            }
            .padding(16)
            .themeSkinSectionCard(cornerRadius: 24)
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "待定".appLocalized }
        return depositLocalizedDateString(date, template: "yMMM")
    }

    private func getDepositStatus() -> String? {
        guard let date = clothing.depositDate else { return nil }
        let now = Date()
        let calendar = Calendar.current

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0

        if days > 0 {
            return "距定金: %d天".appLocalized(days)
        } else if days == 0 {
            return "定金日".appLocalized
        } else {
            return "定金已结束".appLocalized
        }
    }

    private func getFullPaymentReservationStatus() -> String? {
        guard let date = clothing.depositDate else { return nil }
        let now = Date()
        let calendar = Calendar.current

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0

        if days > 0 {
            return "距预约: %d天".appLocalized(days)
        } else if days == 0 {
            return "预约日".appLocalized
        } else {
            return "待签收".appLocalized
        }
    }

    private func getFinalPaymentStatus() -> String? {
        guard let depositDate = clothing.depositDate,
              let finalPaymentDate = clothing.finalPaymentDate else { return nil }

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let depositDay = calendar.startOfDay(for: depositDate)

        let daysFromDeposit = calendar.dateComponents([.day], from: depositDay, to: today).day ?? 0

        if daysFromDeposit < 0 {
            return "还没开定金".appLocalized
        } else if daysFromDeposit == 0 {
            return nil
        } else {
            let daysToFinalPayment = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: finalPaymentDate)).day ?? 0

            if let endDate = clothing.finalPaymentEndDate {
                let daysToEnd = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: endDate)).day ?? 0
                if daysToEnd < 0 {
                    return "尾款已过，请处理".appLocalized
                }
            }

            if daysToFinalPayment > 0 {
                return "距尾款: %d天".appLocalized(daysToFinalPayment)
            } else {
                return nil
            }
        }
    }

    private func saveNoteChange() {
        let now = Date()
        clothing.note = editingNote
        clothing.updatedAt = now
        clothing.lastModified = now

        do {
            try modelContext.save()
            Task { await SharedPersistence.shared.syncWidgetData() }
        } catch {
            print("DepositItemRow: Failed to save note change: \(error)")
        }
    }
}

struct SimpleDepositItemRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    let clothing: Clothing
    @State private var thumbnailImage: UIImage?
    @State private var showEditNoteAlert: Bool = false
    @State private var editingNote: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    // 1. Image
                    if let uiImage = thumbnailImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        CutePlaceholderView(iconSize: 20)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .task {
                                if let imagePath = clothing.imagePaths.first {
                                    let size = CGSize(width: 50, height: 50)
                                    if let cached = ImageManager.shared.cachedImage(fileName: imagePath, targetSize: size) {
                                        self.thumbnailImage = cached
                                        return
                                    }
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                    if Task.isCancelled { return }
                                    self.thumbnailImage = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: size)
                                }
                            }
                    }

                    // 2. Name & Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clothing.name)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(themeManager.primaryTextColor)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)

                        HStack(spacing: 6) {
                            if let date = clothing.reservationGroupingDate {
                                let groupLabel = clothing.isFullPaymentReservation ? "全款".appLocalized : "尾款".appLocalized
                                Text("%@: %@".appLocalized(groupLabel, formatMonth(date)))
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.accentTextColor)
                                    .themeSkinLegibleText(level: .inline, slot: .filterChip)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(themeManager.accentTextColor.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Text(clothing.isFullPaymentReservation ? "预约待定".appLocalized : "尾款待定".appLocalized)
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.tertiaryTextColor)
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            }

                            // 显示数量（当库存大于1时）
                            if clothing.stock > 1 {
                                Text("×\(clothing.stock)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(themeManager.primaryTextColor)
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            }

                            if let brand = clothing.brand {
                                Text(brand.name)
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.secondaryTextColor)
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            }
                        }
                    }

                    Spacer()

                    // 3. Prices
                    VStack(alignment: .trailing, spacing: 2) {
                        if clothing.isFullPaymentReservation {
                            Text("全款¥%@".appLocalized(clothing.fullPaymentReservationTotalAmount.formatted(.number.precision(.fractionLength(0)))))
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                                .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                        } else {
                            Text("定金¥%@".appLocalized(clothing.totalDeposit.formatted(.number.precision(.fractionLength(0)))))
                                .font(.caption)
                                .foregroundStyle(themeManager.accentTextColor)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            Text("尾款¥%@".appLocalized(clothing.totalBalance.formatted(.number.precision(.fractionLength(0)))))
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                                .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                        }
                    }

                    // 4. Note Icon
                    Button {
                        editingNote = clothing.note
                        showEditNoteAlert = true
                    } label: {
                        Image(systemName: clothing.note.isEmpty ? "square.and.pencil" : "text.bubble.fill")
                            .font(.caption)
                            .foregroundStyle(clothing.note.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.brown))
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .alert("修改备注".appLocalized, isPresented: $showEditNoteAlert) {
                        TextField("请输入备注".appLocalized, text: $editingNote)
                        Button("取消".appLocalized, role: .cancel) { }
                        Button("保存".appLocalized) {
                            saveNoteChange()
                        }
                    }
                }

            }
            .padding(16)
            .themeSkinSectionCard(cornerRadius: 24)
    }

    private func saveNoteChange() {
        let now = Date()
        clothing.note = editingNote
        clothing.updatedAt = now
        clothing.lastModified = now

        do {
            try modelContext.save()
            Task { await SharedPersistence.shared.syncWidgetData() }
        } catch {
            print("SimpleDepositItemRow: Failed to save note change: \(error)")
        }
    }

    private func formatMonth(_ date: Date) -> String {
        depositLocalizedDateString(date, template: "MMM")
    }
}

/// 统一配色的标签视图
struct TagView: View {
    @Environment(ThemeManager.self) private var themeManager
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(themeManager.secondaryTextColor)
            .themeSkinLegibleText(level: .inline, slot: .filterChip)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(themeManager.secondaryTextColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// 统一配色的时间轴行视图
struct TimelineRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let title: String
    let date: Date?
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.appLocalized)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(themeManager.primaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                .frame(width: 40, alignment: .leading)

            if let date = date {
                Text(formatDate(date))
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            } else {
                Text("待定".appLocalized)
                    .font(.caption)
                    .foregroundStyle(themeManager.tertiaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            }

            Spacer()

            if let trailing = trailing {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .filterChip)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(themeManager.secondaryTextColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        depositLocalizedDateString(date, template: "yyyyMMdd")
    }
}
