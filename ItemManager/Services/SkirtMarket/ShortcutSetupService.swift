//
//  ShortcutSetupService.swift
//  裙子股市 - 快捷指令安装服务
//
//  提供一键安装快捷指令的功能
//

import Foundation
import UIKit

/// 快捷指令安装服务
@MainActor
final class ShortcutSetupService {
    static let shared = ShortcutSetupService()
    
    /// 快捷指令配置文件（.shortcut格式）
    private let shortcutFileName = "SkirtMarketImporter.shortcut"
    
    /// URL Scheme
    private let urlScheme = "skirtmarket"
    
    private init() {}
    
    // MARK: - 检查快捷指令是否已安装
    
    /// 检查快捷指令是否已安装
    /// 由于iOS无法直接查询，我们通过UserDefaults记录用户是否已安装
    func isShortcutInstalled() -> Bool {
        return UserDefaults.standard.bool(forKey: "skirtmarket_shortcut_installed")
    }
    
    /// 标记快捷指令为已安装
    func markShortcutAsInstalled() {
        UserDefaults.standard.set(true, forKey: "skirtmarket_shortcut_installed")
    }
    
    // MARK: - 安装快捷指令
    
    /// 开始安装快捷指令流程
    func installShortcut(from viewController: UIViewController) {
        let alert = UIAlertController(
            title: "安装快捷指令",
            message: "这将引导您安装「分享商品到裙子股市」快捷指令，让您可以从闲鱼、小红书等App一键分享商品",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "开始安装", style: .default) { _ in
            self.presentInstallationOptions(from: viewController)
        })
        
        viewController.present(alert, animated: true)
    }
    
    /// 展示安装选项
    private func presentInstallationOptions(from viewController: UIViewController) {
        let actionSheet = UIAlertController(
            title: "选择安装方式",
            message: "请选择最适合您的安装方式",
            preferredStyle: .actionSheet
        )
        
        // 方式1：通过iCloud链接安装（推荐）
        actionSheet.addAction(UIAlertAction(
            title: "📱 一键安装（推荐）",
            style: .default
        ) { _ in
            self.installViaiCloudLink()
        })
        
        // 方式2：手动创建
        actionSheet.addAction(UIAlertAction(
            title: "🔧 手动创建（备用）",
            style: .default
        ) { _ in
            self.showManualSetupGuide(from: viewController)
        })
        
        // 方式3：QR码分享
        actionSheet.addAction(UIAlertAction(
            title: "📤 分享快捷指令",
            style: .default
        ) { _ in
            self.shareShortcutQRCode(from: viewController)
        })
        
        actionSheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        // iPad适配
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        viewController.present(actionSheet, animated: true)
    }
    
    // MARK: - 安装方式1：iCloud链接
    
    /// 通过iCloud链接安装
    /// 你需要先在快捷指令App中创建好快捷指令，然后获取iCloud分享链接
    private func installViaiCloudLink() {
        // 这里替换为你实际的iCloud链接
        // 获取方式：
        // 1. 在快捷指令App中创建好快捷指令
        // 2. 长按快捷指令 -> 分享 -> 复制iCloud链接
        let iCloudLink = "https://www.icloud.com/shortcuts/xxxxxxxxxxxx" // 替换为实际链接
        
        guard let url = URL(string: iCloudLink) else {
            print("❌ 无效的iCloud链接")
            return
        }
        
        // 打开iCloud链接，系统会自动跳转到快捷指令App
        UIApplication.shared.open(url) { success in
            if success {
                print("✅ 已打开快捷指令安装页面")
            } else {
                print("❌ 无法打开快捷指令")
            }
        }
    }
    
    // MARK: - 安装方式2：手动创建指南
    
    /// 显示手动创建指南
    private func showManualSetupGuide(from viewController: UIViewController) {
        let guideView = ShortcutSetupGuideView()
        let hostingController = UIHostingController(rootView: guideView)
        hostingController.modalPresentationStyle = .formSheet
        viewController.present(hostingController, animated: true)
    }
    
    // MARK: - 安装方式3：QR码分享
    
    /// 分享QR码
    private func shareShortcutQRCode(from viewController: UIViewController) {
        // 生成包含iCloud链接的QR码
        let qrImage = generateQRCode(from: "https://www.icloud.com/shortcuts/xxxxxxxxxxxx")
        
        let activityItems: [Any] = [
            "安装「裙子股市」快捷指令，一键分享商品信息：",
            qrImage ?? UIImage()
        ]
        
        let activityVC = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // iPad适配
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        viewController.present(activityVC, animated: true)
    }
    
    /// 生成QR码
    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // 高容错率
        
        guard let ciImage = filter.outputImage else { return nil }
        
        // 放大QR码
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledCIImage = ciImage.transformed(by: transform)
        
        return UIImage(ciImage: scaledCIImage)
    }
    
    // MARK: - 快捷指令模板
    
    /// 获取快捷指令的JSON配置
    /// 这个配置可以被导入到快捷指令App中
    func getShortcutJSON() -> [String: Any] {
        return [
            "WFWorkflowClientVersion": "1092.0.2",
            "WFWorkflowClientRelease": "4.0",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": [
                "WFWorkflowIconStartColor": 4292093695,
                "WFWorkflowIconGlyphNumber": 61456
            ],
            "WFWorkflowImportQuestions": [],
            "WFWorkflowTypes": ["NSExtension", "ActionExtension"],
            "WFWorkflowInputContentItemClasses": [
                "WFAppStoreAppContentItem",
                "WFArticleContentItem",
                "WFContactContentItem",
                "WFDateContentItem",
                "WFEmailAddressContentItem",
                "WFGenericFileContentItem",
                "WFImageContentItem",
                "WFiTunesProductContentItem",
                "WFLocationContentItem",
                "WFDCMapsLinkContentItem",
                "WFAVAssetContentItem",
                "WFPDFContentItem",
                "WFPhoneNumberContentItem",
                "WFRichTextContentItem",
                "WFSafariWebPageContentItem",
                "WFStringContentItem",
                "WFURLContentItem"
            ],
            "WFWorkflowActions": [
                // 动作1：获取网页内容
                [
                    "WFWorkflowActionIdentifier": "is.workflow.actions.getwebpagecontents",
                    "WFWorkflowActionParameters": [:]
                ],
                // 动作2：提取商品信息（使用正则或JavaScript）
                [
                    "WFWorkflowActionIdentifier": "is.workflow.actions.runjavascriptonwebpage",
                    "WFWorkflowActionParameters": [
                        "WFJavaScript": getProductExtractionScript()
                    ]
                ],
                // 动作3：编码为JSON
                [
                    "WFWorkflowActionIdentifier": "is.workflow.actions.gettext",
                    "WFWorkflowActionParameters": [
                        "WFTextActionText": [
                            "Value": [
                                "WFSerializationType": "WFTextTokenString",
                                "string": "{{JavaScript的结果}}"
                            ]
                        ]
                    ]
                ],
                // 动作4：URL编码
                [
                    "WFWorkflowActionIdentifier": "is.workflow.actions.urlencode",
                    "WFWorkflowActionParameters": [
                        "WFEncodeMode": "Encode"
                    ]
                ],
                // 动作5：打开App的URL Scheme
                [
                    "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
                    "WFWorkflowActionParameters": [
                        "WFURLActionURL": "skirtmarket://import?data={{URL编码的文本}}",
                        "WFOpenInApp": true
                    ]
                ]
            ],
            "WFWorkflowName": "分享商品到裙子股市"
        ]
    }
    
    /// 商品信息提取脚本（JavaScript）
    private func getProductExtractionScript() -> String {
        return """
        // 提取商品信息
        var result = {
            platform: "",
            title: "",
            price: "",
            url: window.location.href,
            image: "",
            seller: ""
        };
        
        // 根据域名判断平台
        var hostname = window.location.hostname;
        if (hostname.includes("2.taobao.com") || hostname.includes("xianyu")) {
            result.platform = "闲鱼";
            // 闲鱼选择器
            result.title = document.querySelector('h1')?.textContent?.trim() || '';
            result.price = document.querySelector('.price')?.textContent?.trim() || '';
            result.image = document.querySelector('.item-img img')?.src || '';
            result.seller = document.querySelector('.seller-name')?.textContent?.trim() || '';
        } else if (hostname.includes("xiaohongshu")) {
            result.platform = "小红书";
            // 小红书选择器
            result.title = document.querySelector('.title')?.textContent?.trim() || '';
            result.price = document.querySelector('.price')?.textContent?.trim() || '';
        } else if (hostname.includes("taobao")) {
            result.platform = "淘宝";
            // 淘宝选择器
            result.title = document.querySelector('h3')?.textContent?.trim() || '';
            result.price = document.querySelector('.price')?.textContent?.trim() || '';
        }
        
        // 返回JSON字符串
        completion(JSON.stringify(result));
        """
    }
}

// MARK: - 手动设置指南视图

import SwiftUI

struct ShortcutSetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    
    let steps = [
        GuideStep(
            icon: "1.circle.fill",
            title: "打开快捷指令App",
            description: "在iPhone上找到并打开「快捷指令」应用",
            image: "app.shortcuts"
        ),
        GuideStep(
            icon: "2.circle.fill",
            title: "创建新快捷指令",
            description: "点击右上角「+」号，创建新的快捷指令",
            image: "plus.circle"
        ),
        GuideStep(
            icon: "3.circle.fill",
            title: "添加「获取网页内容」",
            description: "在搜索框中输入「网页」，选择「获取网页内容」",
            image: "safari"
        ),
        GuideStep(
            icon: "4.circle.fill",
            title: "添加「在网页上运行JavaScript」",
            description: "搜索「JavaScript」，添加「在网页上运行JavaScript」动作",
            image: "curlybraces"
        ),
        GuideStep(
            icon: "5.circle.fill",
            title: "粘贴脚本代码",
            description: "复制下方提供的脚本代码，粘贴到JavaScript动作中",
            image: "doc.on.clipboard"
        ),
        GuideStep(
            icon: "6.circle.fill",
            title: "添加「打开URL」",
            description: "搜索「URL」，添加「打开URL」动作，输入：skirtmarket://import?data={{JavaScript的结果}}",
            image: "link"
        ),
        GuideStep(
            icon: "7.circle.fill",
            title: "设置快捷指令名称",
            description: "点击顶部「快捷指令」，重命名为「分享商品到裙子股市」",
            image: "pencil"
        ),
        GuideStep(
            icon: "8.circle.fill",
            title: "添加到共享表单",
            description: "点击设置（⚙️）-> 在共享表单中显示，开启此选项",
            image: "square.and.arrow.up"
        )
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 进度指示器
                    ProgressView(value: Double(currentStep + 1), total: Double(steps.count))
                        .padding(.horizontal)
                    
                    Text("步骤 \(currentStep + 1) / \(steps.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // 当前步骤卡片
                    StepCard(step: steps[currentStep])
                    
                    // JavaScript代码（在第5步显示）
                    if currentStep == 4 {
                        JavaScriptCodeView()
                    }
                    
                    // 导航按钮
                    HStack(spacing: 20) {
                        Button("上一步") {
                            withAnimation {
                                currentStep = max(0, currentStep - 1)
                            }
                        }
                        .disabled(currentStep == 0)
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        if currentStep < steps.count - 1 {
                            Button("下一步") {
                                withAnimation {
                                    currentStep = min(steps.count - 1, currentStep + 1)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("完成") {
                                ShortcutSetupService.shared.markShortcutAsInstalled()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("手动安装指南")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

struct GuideStep {
    let icon: String
    let title: String
    let description: String
    let image: String
}

struct StepCard: View {
    let step: GuideStep
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: step.icon)
                .font(.system(size: 48))
                .foregroundColor(.pink)
            
            Text(step.title)
                .font(.title2.bold())
            
            Text(step.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Image(systemName: step.image)
                .font(.system(size: 64))
                .foregroundColor(.pink.opacity(0.3))
                .padding()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct JavaScriptCodeView: View {
    @State private var copied = false
    
    let script = """
    var result = {
        platform: "",
        title: document.title,
        price: "",
        url: window.location.href,
        image: "",
        seller: ""
    };
    
    var hostname = window.location.hostname;
    if (hostname.includes("2.taobao.com")) {
        result.platform = "xianyu";
        result.price = document.querySelector('.price')?.textContent || '';
    } else if (hostname.includes("xiaohongshu")) {
        result.platform = "xiaohongshu";
    }
    
    completion(JSON.stringify(result));
    """
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("JavaScript代码")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    UIPasteboard.general.string = script
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            
            Text(script)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - 使用示例

/*
// 在设置页面中使用
struct SettingsView: View {
    var body: some View {
        List {
            Section("快捷指令") {
                if ShortcutSetupService.shared.isShortcutInstalled() {
                    Label("快捷指令已安装", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button("安装快捷指令") {
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootVC = windowScene.windows.first?.rootViewController {
                            ShortcutSetupService.shared.installShortcut(from: rootVC)
                        }
                    }
                }
            }
        }
    }
}
*/
