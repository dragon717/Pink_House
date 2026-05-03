//
//  DepositItemRow.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData

struct DepositItemRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    let clothing: Clothing
    @State private var showEditNoteAlert: Bool = false
    @State private var editingNote: String = ""
    @State private var thumbnailImage: UIImage?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

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

                        if let brand = clothing.brand {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill") // Placeholder icon
                                    .font(.caption2)
                                Text(brand.name)
                                    .font(.caption)
                            }
                            .foregroundStyle(themeManager.secondaryTextColor)
                        }

                        if clothing.stock > 1 {
                            Text("库存: \(clothing.stock)")
                                .font(.caption)
                                .foregroundStyle(themeManager.tertiaryTextColor)
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
                            Text("全款预约")
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                            Text("¥\(clothing.fullPaymentReservationTotalAmount.formatted(.number.precision(.fractionLength(0))))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                        } else {
                            Text("定金¥\(clothing.totalDeposit.formatted(.number.precision(.fractionLength(0))))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                            Text("尾款¥\(clothing.totalBalance.formatted(.number.precision(.fractionLength(0))))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
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

                if !clothing.isFullPaymentReservation {
                    FinalPaymentWealthButton(clothing: clothing, compact: false)
                }

                // Note Section
                if !clothing.note.isEmpty {
                    Text("备注: \(clothing.note)")
                        .font(.caption)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                        .padding(8)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Footer
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.orange)
                    Text(clothing.isFullPaymentReservation ? "全款预约日期: \(formatDate(clothing.depositDate))" : "预估尾款时间: \(formatDate(clothing.finalPaymentDate))")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Spacer()

                    Button {
                        editingNote = clothing.note
                        showEditNoteAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                            Text("修改备注")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "5D4037"))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .alert("修改备注", isPresented: $showEditNoteAlert) {
                        TextField("请输入备注", text: $editingNote)
                        Button("取消", role: .cancel) { }
                        Button("保存") {
                            saveNoteChange()
                        }
                    }
                }
            }
            .padding(16)
            .themeSkinSectionCard(cornerRadius: 24)
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "待定" }
        return Self.dateFormatter.string(from: date)
    }

    private func getDepositStatus() -> String? {
        guard let date = clothing.depositDate else { return nil }
        let now = Date()
        let calendar = Calendar.current

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0

        if days > 0 {
            return "距定金: \(days)天"
        } else if days == 0 {
            return "定金日"
        } else {
            return "定金已结束"
        }
    }

    private func getFullPaymentReservationStatus() -> String? {
        guard let date = clothing.depositDate else { return nil }
        let now = Date()
        let calendar = Calendar.current

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0

        if days > 0 {
            return "距预约: \(days)天"
        } else if days == 0 {
            return "预约日"
        } else {
            return "已预约"
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
            return "还没开定金"
        } else if daysFromDeposit == 0 {
            return nil
        } else {
            let daysToFinalPayment = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: finalPaymentDate)).day ?? 0

            if let endDate = clothing.finalPaymentEndDate {
                let daysToEnd = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: endDate)).day ?? 0
                if daysToEnd < 0 {
                    return "尾款已过，请处理"
                }
            }

            if daysToFinalPayment > 0 {
                return "距尾款: \(daysToFinalPayment)天"
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

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月"
        return formatter
    }()

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

                        HStack(spacing: 6) {
                            if let date = clothing.reservationGroupingDate {
                                Text("\(clothing.isFullPaymentReservation ? "全款" : "尾款"): \(Self.monthFormatter.string(from: date))")
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.accentTextColor)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(themeManager.accentTextColor.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Text(clothing.isFullPaymentReservation ? "预约待定" : "尾款待定")
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.tertiaryTextColor)
                            }

                            // 显示数量（当库存大于1时）
                            if clothing.stock > 1 {
                                Text("×\(clothing.stock)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(themeManager.primaryTextColor)
                            }

                            if let brand = clothing.brand {
                                Text(brand.name)
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.secondaryTextColor)
                            }
                        }
                    }

                    Spacer()

                    // 3. Prices
                    VStack(alignment: .trailing, spacing: 2) {
                        if clothing.isFullPaymentReservation {
                            Text("全款¥\(clothing.fullPaymentReservationTotalAmount.formatted(.number.precision(.fractionLength(0))))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
                        } else {
                            Text("定金¥\(clothing.totalDeposit.formatted(.number.precision(.fractionLength(0))))")
                                .font(.caption)
                                .foregroundStyle(themeManager.accentTextColor)
                            Text("尾款¥\(clothing.totalBalance.formatted(.number.precision(.fractionLength(0))))")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(themeManager.accentTextColor)
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
                    .alert("修改备注", isPresented: $showEditNoteAlert) {
                        TextField("请输入备注", text: $editingNote)
                        Button("取消", role: .cancel) { }
                        Button("保存") {
                            saveNoteChange()
                        }
                    }
                }

                if !clothing.isFullPaymentReservation {
                    FinalPaymentWealthButton(clothing: clothing, compact: true)
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
}

struct FinalPaymentWealthButton: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query private var wealthSavingEntries: [WealthSavingEntry]
    @State private var showingSavingSheet = false
    @State private var celebrationAmount: Decimal?

    let clothing: Clothing
    var compact: Bool = false

    private var savedAmount: Decimal {
        WealthSavingLedger.activeTotal(for: clothing.id, in: wealthSavingEntries)
    }

    private var paidAmount: Decimal {
        WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: wealthSavingEntries)
    }

    private var finalPaymentRemainingAmount: Decimal {
        WealthSavingLedger.remainingFinalPaymentAmount(for: clothing, entries: wealthSavingEntries)
    }

    private var remainingAmount: Decimal {
        WealthSavingLedger.remainingAssignableAmount(for: clothing, entries: wealthSavingEntries)
    }

    private var overflowAmount: Decimal {
        WealthSavingLedger.overflowAmount(for: clothing, entries: wealthSavingEntries)
    }

    var body: some View {
        Group {
            if !clothing.isFullPaymentReservation {
                Button {
                    showingSavingSheet = true
                } label: {
                    statusLabel(
                        icon: overflowAmount > 0 ? "exclamationmark.triangle.fill" : (savedAmount > 0 ? "tray.full.fill" : "tray.and.arrow.down"),
                        title: overflowAmount > 0 ? "小金库超额" : (paidAmount > 0 ? "尾款支付进度" : (remainingAmount <= 0 ? "已存到上限" : (savedAmount > 0 ? "小金库进度" : "存一笔到小金库"))),
                        detail: overflowAmount > 0 ? "超额¥\(NSDecimalNumber(decimal: overflowAmount).stringValue)" : "已付¥\(NSDecimalNumber(decimal: paidAmount).stringValue) · 剩余¥\(NSDecimalNumber(decimal: finalPaymentRemainingAmount).stringValue) · 可抵扣¥\(NSDecimalNumber(decimal: savedAmount).stringValue)",
                        foreground: overflowAmount > 0 ? Color(hex: "C94C72") : .orange,
                        background: Color.orange.opacity(0.10)
                    )
                }
                .buttonStyle(.plain)
                .disabled(remainingAmount <= 0)
                .sheet(isPresented: $showingSavingSheet) {
                    VaultSavingSheet(
                        targetClothing: clothing,
                        currentSavedAmount: savedAmount,
                        onSave: saveWealthSavingAmount
                    )
                }
                .overlay {
                    if let celebrationAmount {
                        VaultSavingCelebrationOverlay(
                            amount: celebrationAmount,
                            onComplete: { self.celebrationAmount = nil }
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var savedDateText: String {
        guard let date = clothing.finalPaymentSavedAt else { return "已计入来财统计" }
        return "存入于 \(date.formatted(date: .numeric, time: .omitted))"
    }

    private func statusLabel(
        icon: String,
        title: String,
        detail: String,
        foreground: Color,
        background: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.bold))
            if !compact {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(themeManager.secondaryTextColor)
            } else {
                Spacer(minLength: 0)
                Text(detail)
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
        .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 18, showsDecoration: false) {
            Capsule().fill(background)
        }
    }

    private func saveWealthSavingAmount(_ amount: Decimal) {
        do {
            guard let entry = try WealthSavingLedger.addSaving(
                amount: amount,
                for: clothing,
                entries: wealthSavingEntries,
                note: "为「\(clothing.name)」存钱",
                context: modelContext
            ) else { return }
            Task { await SharedPersistence.shared.syncWidgetData() }
            celebrationAmount = entry.amount
        } catch {
            print("FinalPaymentWealthButton: Failed to save wealth saving entry: \(error)")
        }
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(themeManager.primaryTextColor)
                .frame(width: 40, alignment: .leading)

            if let date = date {
                Text(formatDate(date))
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
            } else {
                Text("待定")
                    .font(.caption)
                    .foregroundStyle(themeManager.tertiaryTextColor)
            }

            Spacer()

            if let trailing = trailing {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(themeManager.secondaryTextColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        return Self.dateFormatter.string(from: date)
    }
}
