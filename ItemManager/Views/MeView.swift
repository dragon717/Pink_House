
import SwiftUI
import UniformTypeIdentifiers

struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @State private var isImporting = false
    @State private var showingImportAlert = false
    @State private var importMessage = ""
    
    var body: some View {
        NavigationStack {
            List {
                // Section 1: Account Info
//                Section {
//                    HStack(spacing: 15) {
//                        Image(systemName: "smiley")
//                            .resizable()
//                            .scaledToFit()
//                            .frame(width: 60, height: 60)
//                            .foregroundStyle(.gray)
//                            .padding(10)
//                            .background(Color.gray.opacity(0.1))
//                            .clipShape(Circle())
//                        
//                        VStack(alignment: .leading, spacing: 4) {
//                            Text("用户 6948")
//                                .font(.title3)
//                                .fontWeight(.bold)
//                            Text("189****6948")
//                                .font(.subheadline)
//                                .foregroundStyle(.secondary)
//                        }
//                        
//                        Spacer()
//                        
//                        Image(systemName: "chevron.right")
//                            .foregroundStyle(.gray)
//                            .font(.caption)
//                    }
//                    .padding(.vertical, 4)
//                    
//                    NavigationLink(destination: Text("退出登录")) {
//                        HStack {
//                            Image(systemName: "rectangle.portrait.and.arrow.right")
//                                .foregroundStyle(.brown)
//                                .frame(width: 24)
//                            Text("退出登录")
//                        }
//                    }
//                    
//                    NavigationLink(destination: Text("注销账户")) {
//                        HStack {
//                            Image(systemName: "person.crop.circle.badge.xmark")
//                                .foregroundStyle(.red)
//                                .frame(width: 24)
//                            Text("注销账户")
//                                .foregroundStyle(.red)
//                        }
//                    }
//                } header: {
//                    Text("账户信息")
//                }
                
                // Section 2: Membership
                // Section {
                //     NavigationLink(destination: Text("开通会员")) {
                //         HStack {
                //             Image(systemName: "crown.fill")
                //                 .foregroundStyle(.brown)
                //                 .font(.title2)
                //                 .frame(width: 40, height: 40)
                //                 .background(Color.brown.opacity(0.1))
                //                 .clipShape(Circle())
                            
                //             VStack(alignment: .leading) {
                //                 Text("开通会员")
                //                     .font(.headline)
                //                     .foregroundStyle(.brown)
                //                 Text("解锁全部高级功能")
                //                     .font(.caption)
                //                     .foregroundStyle(.gray)
                //             }
                //         }
                //         .padding(.vertical, 4)
                //     }
                // }
                // .listRowBackground(
                //     LinearGradient(
                //         colors: [Color.white, Color.pink.opacity(0.05)],
                //         startPoint: .leading,
                //         endPoint: .trailing
                //     )
                // )
                
                // Section 3: Feature Settings
                Section {
                    NavigationLink(destination: GeneralSettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.brown)
                                .font(.body)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading) {
                                Text("通用设置")
                                    .font(.body)
                                Text("语言、主题等")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    SettingsRow(icon: "bell", title: "通知设置", subtitle: "管理通知提醒")
                    SettingsRow(icon: "lock", title: "隐私设置", subtitle: "数据与隐私")
                    SettingsRow(icon: "square.grid.2x2", title: "小组件设置", subtitle: "桌面小组件配置")
                    NavigationLink(destination: DataManagementView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "tag")
                                .foregroundStyle(.brown)
                                .font(.body)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading) {
                                Text("标签设置")
                                    .font(.body)
                                Text("管理衣橱标签/品牌/类型等")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Label("功能设置", systemImage: "gearshape")
                }
                
                // Section 4: Data Management (临时用)
//                Section {
//                    Button {
//                        isImporting = true
//                    } label: {
//                        HStack(spacing: 12) {
//                            Image(systemName: "square.and.arrow.down")
//                                .foregroundStyle(.blue)
//                                .font(.body)
//                                .frame(width: 24)
//                            
//                            VStack(alignment: .leading) {
//                                Text("导入其他App备份")
//                                    .font(.body)
//                                    .foregroundStyle(.primary)
//                                Text("支持导入 .backup 格式文件")
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                        }
//                        .padding(.vertical, 2)
//                    }
//                } header: {
//                    Label("数据管理", systemImage: "externaldrive")
//                }
            }
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    themeManager.backgroundColor
                        .ignoresSafeArea()
                    
                    if themeManager.backgroundStyle == .image, let image = themeManager.backgroundImage {
                        SmartBackgroundImage(image: image, opacity: themeManager.backgroundOpacity)
                    }
                    
                    if themeManager.isBlurEnabled {
                        Rectangle().foregroundStyle(.ultraThinMaterial).ignoresSafeArea()
                    }
                }
            }
            .navigationTitle("我的")
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.data], // 允许所有数据类型，或者自定义类型
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    
                    Task {
                        // 在 Task 内部获取权限，确保覆盖整个异步操作
                        guard url.startAccessingSecurityScopedResource() else {
                            importMessage = "无法访问文件，请检查权限"
                            showingImportAlert = true
                            return
                        }
                        
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        do {
                            let result = try await ImportManager.shared.importBackup(from: url, context: modelContext)
                            importMessage = "导入完成\n成功: \(result.successCount)\n失败: \(result.failCount)"
                            if !result.errors.isEmpty {
                                importMessage += "\n\n错误详情:\n" + result.errors.prefix(3).joined(separator: "\n")
                            }
                        } catch {
                            importMessage = "导入失败: \(error.localizedDescription)"
                        }
                        showingImportAlert = true
                    }
                    
                case .failure(let error):
                    importMessage = "选择文件失败: \(error.localizedDescription)"
                    showingImportAlert = true
                }
            }
            .alert("导入结果", isPresented: $showingImportAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(importMessage)
            }
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        NavigationLink(destination: Text(title)) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.brown)
                    .font(.body)
                    .frame(width: 24)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

#Preview {
    MeView()
}
