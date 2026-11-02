import SwiftUI
import UniformTypeIdentifiers

/// 已有 Logo 点击预览，更换使用独立入口；文件先复制到 staging，再保存引用。
struct OpsShopLogoPicker: View {
    @ObservedObject var workspace: OpsWorkspace
    @Binding var reference: String?
    @State private var importsImage = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("店家 Logo").font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                OpsImageUploadThumbnail(
                    url: workspace.previewFileURL(forReference:
                        reference.flatMap { workspace.asset(for: $0)?.originalURL ?? $0 }),
                    size: 64, title: "点击上传或替换店家 Logo") { importsImage = true }
                VStack(alignment: .leading, spacing: 4) {
                    Text(reference == nil ? "点击图片框上传" : "点击图片查看大图").font(.caption).foregroundStyle(.secondary)
                    if reference != nil {
                        Button("清除 Logo") { reference = nil; error = nil }
                            .controlSize(.small)
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .fileImporter(isPresented: $importsImage, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let id = workspace.importSingleImage(from: url) else {
                    error = workspace.lastError ?? "图片导入失败。"; return
                }
                reference = id
                error = workspace.lastError
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
}
