//
//  DataManagementView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/*
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
*/

struct TextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    
    var text: String
    var filename: String?
    
    init(text: String, filename: String = "Export.csv") {
        self.text = text
        self.filename = filename
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var data: Data
    var filename: String?
    
    init(data: Data, filename: String = "Backup.json") {
        self.data = data
        self.filename = filename
    }
    
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            self.data = data
        } else {
            self.data = Data()
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("useCloudSync") private var useCloudSync = false
    
    @State private var showingCSVExporter = false
    @State private var showingBackupExporter = false
    @State private var showingRestoreImporter = false
    @State private var showingRestoreAlert = false
    @State private var showRestartAlert = false
    // @State private var showingShareSheet = false
    // @State private var shareItems: [Any] = []
    
    @State private var exportDocument: TextFile = TextFile(text: "")
    @State private var backupDocument: JSONFile = JSONFile(data: Data())
    @State private var restoreURL: URL?
    
    @State private var message: String?
    @State private var showingMessage = false
    
    var body: some View {
        List {
            Section(header: Text("基础数据管理")) {
                NavigationLink(destination: TagModelManagementView()) {
                    Label("标签管理 (Tags)", systemImage: "tag")
                }
                NavigationLink(destination: BrandManagementView()) {
                    Label("品牌管理 (Brands)", systemImage: "crown")
                }
            }
            
            Section(header: Text("属性数据管理")) {
                NavigationLink(destination: FieldManagementView(title: "类型管理", keyPath: \.types, isCommaSeparated: true)) {
                    Label("类型 (Types)", systemImage: "tshirt")
                }
                
                NavigationLink(destination: FieldManagementView(title: "颜色管理", keyPath: \.colors, isCommaSeparated: true)) {
                    Label("颜色 (Colors)", systemImage: "paintpalette")
                }
                
                NavigationLink(destination: FieldManagementView(title: "尺码管理", keyPath: \.sizes, isCommaSeparated: true)) {
                    Label("尺码 (Sizes)", systemImage: "ruler")
                }
                
                NavigationLink(destination: FieldManagementView(title: "衣长管理", keyPath: \.length, isCommaSeparated: false)) {
                    Label("衣长 (Length)", systemImage: "arrow.up.and.down")
                }
                
                NavigationLink(destination: FieldManagementView(title: "状况管理", keyPath: \.condition, isCommaSeparated: false)) {
                    Label("状况 (Condition)", systemImage: "star")
                }
                
                NavigationLink(destination: FieldManagementView(title: "小物管理", keyPath: \.accessories, isCommaSeparated: true)) {
                    Label("小物 (Accessories)", systemImage: "bag")
                }
            }
            
/*
            Section(header: Text("同步设置")) {
                Toggle(isOn: $useCloudSync) {
                    Label("iCloud 同步 (iCloud Sync)", systemImage: "icloud")
                }
                .onChange(of: useCloudSync) { _, _ in
                    showRestartAlert = true
                }
                
                if useCloudSync {
                    Text("开启后，您的数据将在所有登录相同 iCloud 账号的设备间自动同步。\n注意：图片目前仅支持本地存储，不同步。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
*/
            Section(header: Text("备份与导出")) {
                Button(action: prepareCSVExport) {
                    Label("导出 CSV (Export CSV)", systemImage: "tablecells")
                }
                
                Button(action: prepareBackup) {
                    Label("备份数据 (Backup Data)", systemImage: "externaldrive.badge.plus")
                }
                
                Button(action: { showingRestoreImporter = true }) {
                    Label("恢复数据 (Restore Data)", systemImage: "arrow.clockwise.icloud")
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("数据管理")
        // .sheet(isPresented: $showingShareSheet) {
        //     ShareSheet(items: shareItems)
        // }
        /*
        .fileExporter(isPresented: $showingCSVExporter, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: exportDocument.filename) { result in
            handleExportResult(result)
        }
        .fileExporter(isPresented: $showingBackupExporter, document: backupDocument, contentType: .json, defaultFilename: backupDocument.filename) { result in
            handleExportResult(result)
        }
        */
        .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                self.restoreURL = url
                self.showingRestoreAlert = true
            case .failure(let error):
                self.message = "选择文件失败: \(error.localizedDescription)"
                self.showingMessage = true
            }
        }
        .alert("确认恢复数据？", isPresented: $showingRestoreAlert) {
            Button("取消", role: .cancel) { }
            Button("确认恢复", role: .destructive) {
                performRestore()
            }
        } message: {
            Text("恢复操作将覆盖当前所有数据，且不可撤销。建议先备份当前数据。")
        }
        .alert("提示", isPresented: $showingMessage) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(message ?? "")
        }
        .alert("需重启应用", isPresented: $showRestartAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("更改同步设置需要重启应用才能生效。请手动关闭并重新打开应用。")
        }
    }
    
    private func showShareSheet(url: URL) {
        guard let source = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = source.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        // iPad Popover 配置
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        // 找到最顶层的 presentedViewController 以避免覆盖
        var presentingVC = rootViewController
        while let presented = presentingVC.presentedViewController {
            presentingVC = presented
        }
        
        presentingVC.present(activityVC, animated: true, completion: nil)
    }
    
    private func prepareCSVExport() {
        print("DataManagementView: 准备导出 CSV...")
        do {
            let url = try DataTransferService.shared.exportToCSV(context: modelContext)
            // 直接使用文件 URL 进行分享，更稳定且支持多种分享方式
            DispatchQueue.main.async {
                print("DataManagementView: CSV 准备就绪: \(url)")
                showShareSheet(url: url)
            }
        } catch {
            print("DataManagementView: CSV 导出错误: \(error)")
            DispatchQueue.main.async {
                self.message = "生成 CSV 失败: \(error.localizedDescription)"
                self.showingMessage = true
            }
        }
    }
    
    private func prepareBackup() {
        print("DataManagementView: 准备备份数据...")
        do {
            let url = try DataTransferService.shared.createBackup(context: modelContext)
            // 备份也使用 ShareSheet，统一体验
            DispatchQueue.main.async {
                print("DataManagementView: 备份数据准备就绪: \(url)")
                showShareSheet(url: url)
            }
        } catch {
            print("DataManagementView: 备份生成错误: \(error)")
            DispatchQueue.main.async {
                self.message = "生成备份失败: \(error.localizedDescription)"
                self.showingMessage = true
            }
        }
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            message = "导出成功"
            showingMessage = true
        case .failure(let error):
            message = "导出失败: \(error.localizedDescription)"
            showingMessage = true
        }
    }
    
    private func performRestore() {
        guard let url = restoreURL else { return }
        
        // Accessing security scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            message = "无法访问文件"
            showingMessage = true
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        Task {
            do {
                try await DataTransferService.shared.restoreBackup(from: url, context: modelContext)
                await MainActor.run {
                    message = "数据恢复成功"
                    showingMessage = true
                }
            } catch {
                await MainActor.run {
                    message = "数据恢复失败: \(error.localizedDescription)"
                    showingMessage = true
                }
            }
        }
    }
}
