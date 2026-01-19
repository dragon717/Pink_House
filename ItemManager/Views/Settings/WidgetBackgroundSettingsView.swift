//
//  WidgetBackgroundSettingsView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI
import PhotosUI

struct WidgetBackgroundSettingsView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isDefault: Bool = true
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        Form {
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
                Text("当前背景预览")
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
        }
        .navigationTitle("小组件背景")
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

#Preview {
    NavigationStack {
        WidgetBackgroundSettingsView()
    }
}
