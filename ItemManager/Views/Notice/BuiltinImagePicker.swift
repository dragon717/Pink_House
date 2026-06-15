import SwiftUI

// MARK: - 内置图片选择器
// 用于调试版选择应用自带的图片作为公告媒体

struct BuiltinImagePicker: View {
    @Binding var selectedImageName: String?
    @Binding var selectedImageData: Data?
    @Environment(\.dismiss) private var dismiss

    // 内置图片列表 - 从 Assets.xcassets 中选择
    private let builtinImages = [
        "notice_bg",
        "card_front",
        "card_back",
        "sleepy_cat",
        "thinking_cat",
        "angry_cat",
        "curious_cat",
        "happy_cat",
        "maomao_left_front",
        "maomao_right_back",
        "naicha_left_front",
        "naicha_right_back",
        "SplashScreen",
        "maomao_dragging",
        "maomao_peeking",
        "maomao_portrait",
        "naicha_portrait",
        "ootd",
        "naicha_dragging",
        "naicha_peeking"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(builtinImages, id: \.self) { imageName in
                        ImageCell(
                            imageName: imageName,
                            isSelected: selectedImageName == imageName
                        ) {
                            selectImage(imageName)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("选择内置图片".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".appLocalized) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button("清除选择".appLocalized) {
                        selectedImageName = nil
                        selectedImageData = nil
                    }
                    .disabled(selectedImageName == nil)
                }
            }
        }
    }

    private func selectImage(_ imageName: String) {
        selectedImageName = imageName

        // 从 Assets 加载图片数据
        if let uiImage = UIImage(named: imageName),
           let data = uiImage.jpegData(compressionQuality: 0.8) {
            selectedImageData = data
            print("✅ 选择内置图片: \(imageName), 大小: \(data.count) bytes")
        } else {
            print("❌ 无法加载图片: \(imageName)")
            selectedImageData = nil
        }

        dismiss()
    }
}

// MARK: - 图片单元格
struct ImageCell: View {
    let imageName: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                    )

                Text(imageName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .blue : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 预览
#Preview {
    BuiltinImagePicker(
        selectedImageName: .constant(nil),
        selectedImageData: .constant(nil)
    )
}
