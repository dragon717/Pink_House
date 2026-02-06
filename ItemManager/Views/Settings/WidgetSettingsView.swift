//
//  WidgetSettingsView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI
import PhotosUI

struct WidgetSettingsView: View {
    // MARK: - Background Settings State
    @State private var selectedItem: PhotosPickerItem?
    @State private var editingFamily: WidgetFamilyType? // 当前正在编辑的尺寸
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var cropRequest: CropRequest?
    @State private var isLoadingImage = false
    
    // Preview Images State
    @State private var smallImage: UIImage?
    @State private var mediumImage: UIImage?
    @State private var largeImage: UIImage?
    @State private var commonImage: UIImage?
    
    // State to trigger refresh
    @State private var refreshID = UUID()
    
    var body: some View {
        Form {
            // MARK: - Multi-Size Background Section
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("分别为不同尺寸的小组件设置背景，或设置一张通用背景。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            // Small
                            WidgetPreviewCard(
                                title: "小号 (Small)",
                                image: smallImage ?? commonImage,
                                aspectRatio: 1.0,
                                isSpecific: smallImage != nil
                            ) {
                                startEditing(family: .small)
                            }
                            
                            // Medium
                            WidgetPreviewCard(
                                title: "中号 (Medium)",
                                image: mediumImage ?? commonImage,
                                aspectRatio: 2.14, // 158/338 approx
                                width: 200,
                                isSpecific: mediumImage != nil
                            ) {
                                startEditing(family: .medium)
                            }
                            
                            // Large
                            WidgetPreviewCard(
                                title: "大号 (Large)",
                                image: largeImage ?? commonImage,
                                aspectRatio: 0.95, // 338/354 approx
                                isSpecific: largeImage != nil
                            ) {
                                startEditing(family: .large)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 0))
            } header: {
                Text("分尺寸设置")
            }
            
            // MARK: - Common Background Section
            Section {
                Button {
                    startEditing(family: .common)
                } label: {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                            .foregroundStyle(.pink)
                        Text("设置通用背景 (默认)")
                        Spacer()
                        if commonImage != nil {
                            Text("已设置")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isLoadingImage)
                
                if hasAnyCustomBackground {
                    Button(role: .destructive) {
                        WidgetBackgroundManager.shared.deleteAllImages()
                        loadCurrentStatus()
                        alertMessage = "已恢复默认背景"
                        showingAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("恢复默认背景 (清除所有)")
                        }
                    }
                }
            } header: {
                Text("通用设置")
            } footer: {
                if isLoadingImage {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("正在处理图片...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            
            // MARK: - Tutorial Section
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 20) {
                        TutorialStepRow(
                            number: 1,
                            title: "回到主屏幕",
                            description: "按下 Home 键或上滑回到 iPhone 主屏幕，长按空白处直到图标开始抖动。",
                            icon: "iphone.homebutton"
                        )
                        
                        TutorialStepRow(
                            number: 2,
                            title: "搜索添加",
                            description: "点击左上角的“+”号，搜索“少女心愿衣橱”。",
                            icon: "plus.app"
                        )
                        
                        TutorialStepRow(
                            number: 3,
                            title: "选择尺寸",
                            description: "左右滑动选择您喜欢的尺寸（小/中/大），然后点击“添加小组件”。",
                            icon: "square.resize"
                        )
                        
                        TutorialStepRow(
                            number: 4,
                            title: "个性化配置",
                            description: "长按已添加的小组件，选择“编辑小组件”，可以切换【按月份】或【按系列】统计。",
                            icon: "slider.horizontal.3"
                        )
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("💡 小贴士")
                                .font(.headline)
                                .foregroundStyle(.pink)
                            
                            Text("小组件支持深色模式，且在 iOS 17+ 待机模式下有更好的显示效果。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.pink.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.vertical, 8)
                } label: {
                    Label("如何添加桌面小组件？", systemImage: "questionmark.circle")
                        .foregroundStyle(.brown)
                }
            } header: {
                Text("帮助与教程")
            }
        }
        .navigationTitle("小组件设置")
        // Hidden PhotosPicker to be triggered programmatically
        .photosPicker(isPresented: $showingPhotosPicker, selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { _, newItem in
            handleImageSelection(newItem)
        }
        .fullScreenCover(item: $cropRequest) { request in
            // Determine aspect ratio based on editingFamily
            let ratio = editingFamily?.aspectRatio
            
            ImageCropView(image: request.image, aspectRatio: ratio) { croppedImage in
                if let family = editingFamily {
                    WidgetBackgroundManager.shared.saveImage(croppedImage, for: family)
                    loadCurrentStatus()
                    alertMessage = "\(family.displayName)背景设置成功！"
                    showingAlert = true
                }
                
                cropRequest = nil
                editingFamily = nil
            } onCancel: {
                cropRequest = nil
                editingFamily = nil
            }
        }
        .onAppear {
            loadCurrentStatus()
        }
        .alert("提示", isPresented: $showingAlert) {
            Button("好的", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    @State private var showingPhotosPicker = false
    
    private func startEditing(family: WidgetFamilyType) {
        self.editingFamily = family
        self.showingPhotosPicker = true
    }
    
    private func handleImageSelection(_ newItem: PhotosPickerItem?) {
        guard let newItem = newItem else { return }
        isLoadingImage = true
        Task {
            if let data = try? await newItem.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                
                let optimizedImage = await uiImage.preparingThumbnail(of: CGSize(width: 2000, height: 2000)) ?? uiImage
                
                await MainActor.run {
                    self.cropRequest = CropRequest(image: optimizedImage, isNewSelection: true)
                    self.selectedItem = nil
                    self.isLoadingImage = false
                }
            } else {
                await MainActor.run {
                    self.isLoadingImage = false
                }
            }
        }
    }
    
    private var hasAnyCustomBackground: Bool {
        smallImage != nil || mediumImage != nil || largeImage != nil || commonImage != nil
    }
    
    private func loadCurrentStatus() {
        // Load specific images
        if WidgetBackgroundManager.shared.hasSpecificImage(for: .small) {
            self.smallImage = WidgetBackgroundManager.shared.loadImage(for: .small)
        } else {
            self.smallImage = nil
        }
        
        if WidgetBackgroundManager.shared.hasSpecificImage(for: .medium) {
            self.mediumImage = WidgetBackgroundManager.shared.loadImage(for: .medium)
        } else {
            self.mediumImage = nil
        }
        
        if WidgetBackgroundManager.shared.hasSpecificImage(for: .large) {
            self.largeImage = WidgetBackgroundManager.shared.loadImage(for: .large)
        } else {
            self.largeImage = nil
        }
        
        // Load common image
        self.commonImage = WidgetBackgroundManager.shared.loadImage(for: .common)
    }
}

// MARK: - Components

struct WidgetPreviewCard: View {
    let title: String
    let image: UIImage?
    let aspectRatio: CGFloat
    var width: CGFloat = 100
    let isSpecific: Bool
    let action: () -> Void
    
    var body: some View {
        VStack {
            Button(action: action) {
                ZStack {
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .frame(width: width)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSpecific ? Color.pink : Color.secondary.opacity(0.3), lineWidth: isSpecific ? 2 : 1)
                            )
                    } else {
                        // Default Preview
                        DreamyBackgroundPreview()
                            .frame(width: width, height: width / aspectRatio)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .overlay {
                                Image(systemName: "plus")
                                    .foregroundStyle(.white)
                                    .font(.title)
                                    .shadow(radius: 2)
                            }
                    }
                    
                    // Badge if specific
                    if isSpecific {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.pink)
                                    .background(Circle().fill(.white))
                                    .padding(4)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isSpecific ? .pink : .primary)
        }
    }
}

// App 端预览用的梦幻背景 (复制自 Widget 代码以解耦 Target)
struct DreamyBackgroundPreview: View {
    @State private var timeFactor: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. 基础粉色渐变底色
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.88, blue: 0.92), // 较深的樱花粉
                        Color(red: 1.0, green: 0.80, blue: 0.88)  // 偏紫的粉色
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // 光斑 A: 亮粉色 (提亮)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.92, blue: 0.96, opacity: 0.5),
                                Color(red: 1.0, green: 0.92, blue: 0.96, opacity: 0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.8
                        )
                    )
                    .frame(width: geometry.size.width * 1.5, height: geometry.size.width * 1.5)
                    .offset(
                        x: cos(timeFactor / 3600) * 30,
                        y: sin(timeFactor / 3600) * 30
                    )
                
                // 光斑 B: 深粉色 (增加饱和度)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.70, blue: 0.80, opacity: 0.4),
                                Color(red: 1.0, green: 0.70, blue: 0.80, opacity: 0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.5
                        )
                    )
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .offset(
                        x: -cos(timeFactor / 1800) * 50,
                        y: -sin(timeFactor / 1800) * 50
                    )
                
                // 光斑 C: 梦幻紫
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.90, green: 0.70, blue: 0.90, opacity: 0.3),
                                Color(red: 0.90, green: 0.70, blue: 0.90, opacity: 0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.6
                        )
                    )
                    .frame(width: geometry.size.width * 1.2, height: geometry.size.width * 1.2)
                    .position(x: geometry.size.width, y: geometry.size.height)
                
                // 3. 叠加暖色滤镜
                Color(red: 1.0, green: 0.60, blue: 0.75, opacity: 0.1)
                    .blendMode(.overlay)
            }
        }
        .onAppear {
            timeFactor = Date().timeIntervalSince1970
        }
    }
}

struct TutorialStepRow: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.brown.opacity(0.1))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.brown)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationStack {
        WidgetSettingsView()
    }
}
