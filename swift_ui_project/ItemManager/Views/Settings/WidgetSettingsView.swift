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
    @State private var selectedImage: UIImage?
    @State private var isDefault: Bool = true
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        Form {
            // MARK: - Background Settings Section
            Section {
                ZStack {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        // Default preview
                        ZStack {
                            // 使用与 Widget 一致的梦幻背景
                            DreamyBackgroundPreview()
                            
                            VStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.largeTitle)
                                    .foregroundStyle(.pink.opacity(0.5))
                                Text("当前使用梦幻粉白动态背景")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .listRowInsets(EdgeInsets())
                .padding()
            } header: {
                Text("背景设置")
            } footer: {
                Text("设置的背景图将应用到所有尺寸的桌面小组件。")
            }
            
            Section {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        .foregroundStyle(.pink)
                        Text("从相册选择新背景")
                    }
                }
                
                if !isDefault {
                    Button(role: .destructive) {
                        WidgetBackgroundManager.shared.deleteImage()
                        loadCurrentStatus()
                        alertMessage = "已恢复默认背景"
                        showingAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("恢复默认背景")
                        }
                    }
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
        .onChange(of: selectedItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    WidgetBackgroundManager.shared.saveImage(uiImage)
                    await MainActor.run {
                        loadCurrentStatus()
                        alertMessage = "背景设置成功！\n请回到桌面查看小组件变化。"
                        showingAlert = true
                    }
                }
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
    
    private func loadCurrentStatus() {
        if let image = WidgetBackgroundManager.shared.loadImage() {
            self.selectedImage = image
            self.isDefault = false
        } else {
            self.selectedImage = nil
            self.isDefault = true
        }
    }
}

// MARK: - Components

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
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: icon)
                        .foregroundStyle(.pink)
                }
                
                Text(description)
                    .font(.caption)
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
