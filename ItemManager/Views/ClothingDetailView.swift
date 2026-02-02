//
//  ClothingDetailView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/17/26.
//

import SwiftUI
import SwiftData

struct ClothingDetailView: View {
    @Bindable var clothing: Clothing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingConfirmPaymentAlert = false
    @State private var currentImageIndex = 0
    
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - Image Carousel
                        // Adjust height based on orientation (portrait vs landscape)
                        let carouselHeight = geometry.size.height > geometry.size.width ? 400.0 : geometry.size.height * 0.7
                        imageCarousel(height: carouselHeight)
                        
                        // MARK: - Main Info Card
                        mainInfoCard
                            .padding(.horizontal)
                            .offset(y: -40) // Overlap the image slightly
                        
                        // MARK: - Detail Info
                        detailInfoCard
                            .padding(.horizontal)
                            .offset(y: -40)
                        
                        // MARK: - Price Info
                        priceInfoCard
                            .padding(.horizontal)
                            .offset(y: -40)
                        
                        // MARK: - Purchase Info
                        purchaseInfoCard
                            .padding(.horizontal)
                            .offset(y: -40)
                        
                        // MARK: - Pay Balance Button
                        if clothing.isDepositPlan {
                            Button {
                                showingConfirmPaymentAlert = true
                            } label: {
                                Text("已付尾款")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.pink)
                                    .cornerRadius(16)
                            }
                            .padding(.horizontal)
                            .offset(y: -40)
                            .shadow(color: .pink.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        
                        // MARK: - Metadata Info (Created/Updated)
                        VStack(spacing: 4) {
                            Text("添加时间: \(clothing.createdAt.formatted(date: .numeric, time: .shortened))")
                            Text("修改时间: \(clothing.updatedAt.formatted(date: .numeric, time: .shortened))")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 20)
                        .offset(y: -20)
                        
                        // Bottom Padding for FAB
                        Color.clear.frame(height: 80)
                    }
                }
                .ignoresSafeArea(edges: .top)
                
                // MARK: - Custom Navigation Bar
                customNavBar
                
                // MARK: - FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            // Action for Community/Square
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.title2)
                                Text("社区")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .shadow(radius: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                ClothingEditView(clothing: clothing)
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                NotificationManager.shared.cancelNotification(for: clothing)
                // Soft delete
                clothing.isDeleted = true
                clothing.deletedAt = Date()
                Task { await SharedPersistence.shared.syncWidgetData() }
                dismiss()
            }
        } message: {
            Text("确定要删除这件裙子吗？它将被移动到回收站，你可以随时恢复。")
        }
        .alert("确认已付尾款", isPresented: $showingConfirmPaymentAlert) {
            Button("取消", role: .cancel) { }
            Button("确认", role: .none) {
                confirmPayment()
            }
        } message: {
            Text("确认后将移除尾款天使，并清空定金和预估尾款时间信息。")
        }
        .onAppear {
            // 进入详情页时，若定金和尾款 存在，自动重算总价并保存
            if clothing.deposit > 0 || clothing.balance > 0 {
                let newTotal = clothing.deposit + clothing.balance
                if clothing.price != newTotal {
                    clothing.price = newTotal
                }
            }
        }
    }
    
    private func confirmPayment() {
        // Cancel notification since it's no longer a deposit plan
        NotificationManager.shared.cancelNotification(for: clothing)
        
        // Calculate total price if currently 0
        if clothing.price == 0 {
            clothing.price = clothing.deposit + clothing.balance + clothing.accessoriesPrice
        }
        
        clothing.isDepositPlan = false
        clothing.depositDate = nil
        clothing.finalPaymentDate = nil
        clothing.finalPaymentEndDate = nil
        // Try to save context (though it autosaves usually)
        try? modelContext.save()
        Task { await SharedPersistence.shared.syncWidgetData() }
    }
    
    private func duplicateClothing() {
        let newClothing = Clothing(
            name: clothing.name,
            brand: clothing.brand,
            types: clothing.types,
            colors: clothing.colors,
            sizes: clothing.sizes,
            length: clothing.length,
            condition: clothing.condition,
            accessories: clothing.accessories,
            imagePaths: clothing.imagePaths,
            isShared: clothing.isShared,
            originalPrice: clothing.originalPrice,
            price: clothing.price,
            deposit: clothing.deposit,
            balance: clothing.balance,
            accessoriesPrice: clothing.accessoriesPrice,
            purchaseDate: clothing.purchaseDate,
            depositDate: clothing.depositDate,
            isDepositPlan: clothing.isDepositPlan,
            finalPaymentDate: clothing.finalPaymentDate,
            finalPaymentEndDate: clothing.finalPaymentEndDate,
            note: clothing.note,
            stock: clothing.stock,
            status: clothing.status
        )
        
        newClothing.tags = clothing.tags
        
        // Duplicate accessory items
        if let items = clothing.accessoryItems {
            newClothing.accessoryItems = items.map { item in
                AccessoryItem(name: item.name, price: item.price, sortIndex: item.sortIndex)
            }
        }
        
        // Increment reference count for images
        for imagePath in clothing.imagePaths {
            ImageManager.shared.incrementRefCount(fileName: imagePath, context: modelContext)
        }
        
        modelContext.insert(newClothing)
        
        // Schedule notification for the copy
        NotificationManager.shared.scheduleNotification(for: newClothing)
        
        Task { await SharedPersistence.shared.syncWidgetData() }
        
        dismiss()
    }
    
    // MARK: - Subviews
    
    private func imageCarousel(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentImageIndex) {
                if clothing.imagePaths.isEmpty {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "tshirt")
                                .font(.system(size: 60))
                                .foregroundStyle(.pink.opacity(0.3))
                        }
                        .tag(0)
                } else {
                    ForEach(0..<clothing.imagePaths.count, id: \.self) { index in
                        // Estimate target size based on screen scale
                        // Use a reasonable max limit to avoid excessive memory on very large screens or high res assets
                        let scale = UIScreen.main.scale
                        let width = UIScreen.main.bounds.width * scale
                        let targetHeight = height * scale
                        let targetSize = CGSize(width: min(width, 2048), height: min(targetHeight, 2048))
                        
                        CarouselItemView(imagePath: clothing.imagePaths[index], targetSize: targetSize)
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: height)
            
            // Page Indicator Overlay
            if !clothing.imagePaths.isEmpty {
                HStack(spacing: 4) {
                    Text("\(currentImageIndex + 1)")
                    Text("/")
                    Text("\(clothing.imagePaths.count)")
                }
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(.bottom, 60) // Adjust based on overlap
            }
        }
    }
    
    private var customNavBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white))
                    .shadow(radius: 2)
            }
            
            Spacer()
            
            Text("衣橱详情")
                .font(.headline)
                .foregroundStyle(.white)
                .shadow(radius: 2)
            
            Spacer()
            
            Menu {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                
                Button {
                    duplicateClothing()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white))
                    .shadow(radius: 2)
            }
        }
        .padding(.horizontal)
    }
    
    private var mainInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(clothing.name)
                    .font(.title2)
                    .bold()
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("追根溯源") // This could be dynamic based on status
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.brown))
            }
            
            if let tags = clothing.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(tags) { tag in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: tag.colorHex).opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                if let brand = clothing.brand {
                    Circle()
                        .fill(Color(hex: brand.colorHex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(brand.name.prefix(1))
                                .font(.caption2)
                                .foregroundStyle(.white)
                        )
                    Text(brand.name)
                        .font(.subheadline)
                } else {
                    Text("暂无品牌信息")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if clothing.isDepositPlan {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("尾款天使")
                            .font(.caption)
                            .bold()
                    }
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.pink.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var detailInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("裙子信息", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.brown)
            
            ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                if visibilityManager.isVisible(field) {
                    buildDetailRow(for: field)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    @ViewBuilder
    private func buildDetailRow(for field: ClothingField) -> some View {
        switch field {
        case .types:
            InfoRow(label: "类型", value: clothing.types.isEmpty ? "未填写" : clothing.types)
        case .colors:
            InfoRow(label: "颜色", value: clothing.colors.isEmpty ? "未填写" : clothing.colors)
        case .sizes:
            InfoRow(label: "尺码", value: clothing.sizes.isEmpty ? "未填写" : clothing.sizes)
        case .length:
            InfoRow(label: "衣长", value: clothing.length.isEmpty ? "未填写" : clothing.length)
        case .condition:
            InfoRow(label: "状态", value: clothing.condition)
        case .accessories:
            InfoRow(label: "小物", value: clothing.accessories.isEmpty ? "无" : clothing.accessories)
        }
    }
    
    private var priceInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("价格信息", systemImage: "yensign.circle.fill")
                .font(.headline)
                .foregroundStyle(.brown)
            
            if clothing.isDepositPlan {
                // Show total deposit/balance including accessories
                InfoRow(label: "总定金", value: "¥\(clothing.totalDeposit.formatted(.number.precision(.fractionLength(0))))")
                InfoRow(label: "总尾款", value: "¥\(clothing.totalBalance.formatted(.number.precision(.fractionLength(0))))")
                
                Divider()
                
                // Show Breakdown for Dress
                InfoRow(label: "裙子定金", value: "¥\(clothing.deposit.formatted(.number.precision(.fractionLength(0))))")
                InfoRow(label: "裙子尾款", value: "¥\(clothing.balance.formatted(.number.precision(.fractionLength(0))))")
            }
            
            if clothing.originalPrice > 0 {
                InfoRow(label: "原价", value: "¥\(clothing.originalPrice.formatted(.number.precision(.fractionLength(0))))")
            }
            
            InfoRow(label: "裙子单价", value: "¥\(clothing.price.formatted(.number.precision(.fractionLength(0))))")
            
            if clothing.stock > 1 {
                InfoRow(label: "库存数量", value: "\(clothing.stock)")
                InfoRow(label: "裙子总价", value: "¥\((clothing.price * Decimal(clothing.stock)).formatted(.number.precision(.fractionLength(0))))")
            }
            
            if let items = clothing.accessoryItems, !items.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("小物明细")
                        Spacer()
                        Text("小物总价: ¥\(items.reduce(Decimal(0)) { $0 + $1.price }.formatted(.number.precision(.fractionLength(0...2))))")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    
                    ForEach(items.sorted(by: { $0.sortIndex < $1.sortIndex })) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.name.isEmpty ? "未命名小物" : item.name)
                                Spacer()
                                Text("¥\(NSDecimalNumber(decimal: item.price).doubleValue.formatted(.number.precision(.fractionLength(0...2))))")
                            }
                            
                            // Show deposit/balance for accessory if it exists
                            if item.deposit > 0 || item.balance > 0 {
                                HStack {
                                    if item.deposit > 0 {
                                        Text("定金: ¥\(item.deposit.formatted(.number.precision(.fractionLength(0...2))))")
                                    }
                                    if item.balance > 0 {
                                        Text("尾款: ¥\(item.balance.formatted(.number.precision(.fractionLength(0...2))))")
                                    }
                                    Spacer()
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
            
            HStack {
                Label("合计金额", systemImage: "star.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                
                let totalUnit = clothing.price + clothing.accessoriesPrice
                let totalAll = totalUnit * Decimal(clothing.stock)
                
                Text("¥\(totalAll.formatted(.number.precision(.fractionLength(0))))")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.brown)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
            
            if clothing.stock > 1 {
                Text("包含 \(clothing.stock) 件库存，单套价值 ¥\((clothing.price + clothing.accessoriesPrice).formatted(.number.precision(.fractionLength(0))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var purchaseInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("购买信息", systemImage: "bag.fill")
                .font(.headline)
                .foregroundStyle(.brown)
            
            InfoRow(label: "购买日期", value: clothing.purchaseDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
            
            if clothing.isDepositPlan {
                if let depositDate = clothing.depositDate {
                    InfoRow(label: "定金日期", value: depositDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                }
                if let finalPaymentDate = clothing.finalPaymentDate {
                    InfoRow(label: "预估尾款", value: formatFinalPaymentDate(start: finalPaymentDate, end: clothing.finalPaymentEndDate))
                }
            }
            
            let duration = Calendar.current.dateComponents([.day], from: clothing.purchaseDate, to: Date()).day ?? 0
            InfoRow(label: "拥有时长", value: "\(duration)天")
            
            if clothing.balance > 0 {
                // 如果是尾款天使，显示总尾款（含小物），否则只显示裙子尾款（因为普通模式下可能不怎么关注小物尾款，或者也可以统一显示总尾款）
                // 需求是：加入尾款天使的，自定义小物的定金和裙子的定金 加合显示... 尾款也同理
                if clothing.isDepositPlan {
                    InfoRow(label: "总尾款金额", value: "¥\(clothing.totalBalance.formatted(.number.precision(.fractionLength(0))))")
                } else {
                    InfoRow(label: "尾款金额", value: "¥\(clothing.balance.formatted(.number.precision(.fractionLength(0))))")
                }
            }
            
            if !clothing.note.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("备注")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(clothing.note)
                        .font(.body)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func formatFinalPaymentDate(start: Date, end: Date?) -> String {
        let startDateString = start.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
        
        if let endDate = end {
            // Check if end date is different from start date (ignoring time)
            let calendar = Calendar.current
            if !calendar.isDate(start, inSameDayAs: endDate) {
                let endDateString = endDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
                return "\(startDateString) - \(endDateString)"
            }
        }
        
        return startDateString
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: iconForLabel(label))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
    
    private func iconForLabel(_ label: String) -> String {
        switch label {
        case "类型": return "tshirt"
        case "颜色": return "paintpalette"
        case "尺码": return "ruler"
        case "衣长": return "arrow.up.and.down"
        case "状态": return "star.circle"
        case "小物": return "sparkles"
        case "裙子总价", "裙子单价", "原价": return "tag"
        case "库存数量": return "number.circle"
        case "购买日期": return "calendar"
        case "定金日期": return "calendar.badge.clock"
        case "预估尾款": return "hourglass"
        case "拥有时长": return "clock"
        case "尾款金额": return "creditcard"
        default: return "circle"
        }
    }
}

struct CarouselItemView: View {
    let imagePath: String
    let targetSize: CGSize
    
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .task {
            self.image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: targetSize)
        }
    }
}
