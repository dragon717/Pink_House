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
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.96, blue: 0.96),
                                    Color(red: 1.0, green: 0.92, blue: 0.94)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.pink.opacity(0.5))
                                Text("当前使用默认樱花粉背景")
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
