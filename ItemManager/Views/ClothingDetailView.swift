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
    @State private var currentImageIndex = 0
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Image Carousel
                    imageCarousel
                    
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
        .navigationBarHidden(true)
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                ClothingEditView(clothing: clothing)
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                modelContext.delete(clothing)
                dismiss()
            }
        } message: {
            Text("确定要删除这件裙子吗？此操作无法撤销。")
        }
    }
    
    // MARK: - Subviews
    
    private var imageCarousel: some View {
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
                        if let image = ImageManager.shared.loadImage(fileName: clothing.imagePaths[index]) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .tag(index)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .tag(index)
                        }
                    }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: 400)
            
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
            
            if let brand = clothing.brand {
                HStack {
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
                    Spacer()
                }
            } else {
                Text("暂无品牌信息")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var detailInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("裙子信息", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.brown)
            
            InfoRow(label: "类型", value: clothing.types.isEmpty ? "未填写" : clothing.types)
            InfoRow(label: "颜色", value: clothing.colors.isEmpty ? "未填写" : clothing.colors)
            InfoRow(label: "尺码", value: clothing.sizes.isEmpty ? "未填写" : clothing.sizes)
            InfoRow(label: "小物", value: clothing.accessories.isEmpty ? "无" : clothing.accessories)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var priceInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("价格信息", systemImage: "yensign.circle.fill")
                .font(.headline)
                .foregroundStyle(.brown)
            
            InfoRow(label: "裙子总价", value: "¥\(clothing.price.formatted(.number.precision(.fractionLength(0))))")
            
            HStack {
                Label("总价", systemImage: "star.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("¥\((clothing.price + clothing.accessoriesPrice).formatted(.number.precision(.fractionLength(0))))")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.brown)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var purchaseInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("购买信息", systemImage: "bag.fill")
                .font(.headline)
                .foregroundStyle(.brown)
            
            InfoRow(label: "购买日期", value: clothing.purchaseDate.formatted(date: .long, time: .omitted))
            
            let duration = Calendar.current.dateComponents([.day], from: clothing.purchaseDate, to: Date()).day ?? 0
            InfoRow(label: "拥有时长", value: "\(duration)天")
            
            if clothing.balance > 0 {
                InfoRow(label: "尾款金额", value: "¥\(clothing.balance.formatted(.number.precision(.fractionLength(0))))")
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
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
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
        case "小物": return "sparkles"
        case "裙子总价": return "tag"
        case "购买日期": return "calendar"
        case "拥有时长": return "clock"
        case "尾款金额": return "creditcard"
        default: return "circle"
        }
    }
}
