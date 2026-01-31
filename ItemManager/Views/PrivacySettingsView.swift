import SwiftUI
import Photos
import AVFoundation

struct PrivacySettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    
    // 价格显示设置
    @AppStorage("privacyShowPrice") private var showPrice = true
    @AppStorage("privacyShowOriginalPrice") private var showOriginalPrice = true
    
    @State private var photoAuthStatus: PHAuthorizationStatus = .notDetermined
    @State private var cameraAuthStatus: AVAuthorizationStatus = .notDetermined
    
    var body: some View {
        List {
            Section {
                Toggle("在列表中显示入库价格", isOn: $showPrice)
                Toggle("在列表中显示原价", isOn: $showOriginalPrice)
            } header: {
                Text("价格显示")
            } footer: {
                Text("关闭后，衣柜列表将不再显示对应的价格信息，保护您的隐私。")
            }
            
            Section {
                // 照片权限
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.body)
                        .foregroundStyle(.brown)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("照片访问权限")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text(photoStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if showGoToSettings(for: photoAuthStatus) {
                        Button("去设置") {
                            openSettings()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.brown)
                    } else {
                        Text(statusLabel(for: photoAuthStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                
                // 相机权限
                HStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.body)
                        .foregroundStyle(.brown)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("相机访问权限")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text(cameraStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if showGoToSettings(for: cameraAuthStatus) {
                        Button("去设置") {
                            openSettings()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.brown)
                    } else {
                        Text(statusLabel(for: cameraAuthStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("系统权限")
            } footer: {
                Text("如果您无法使用拍照或选择照片功能，请检查是否允许应用访问相机和照片。")
            }
        }
        .navigationTitle("隐私设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkPermissions()
            // 监听应用从后台返回前台的通知，以便用户在设置中修改权限后返回App能刷新状态
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                checkPermissions()
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    private func checkPermissions() {
        // 检查相册权限
        // readWrite 是 iOS 14+ 的，如果为了兼容性可以做判断，但这里假设较新系统
        photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        // 检查相机权限
        cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private var photoStatusText: String {
        switch photoAuthStatus {
        case .authorized:
            return "已允许访问所有照片"
        case .limited:
            return "已允许访问部分照片"
        case .denied, .restricted:
            return "未允许访问照片"
        case .notDetermined:
            return "尚未请求权限"
        @unknown default:
            return "未知状态"
        }
    }
    
    private var cameraStatusText: String {
        switch cameraAuthStatus {
        case .authorized:
            return "已允许使用相机"
        case .denied, .restricted:
            return "未允许使用相机"
        case .notDetermined:
            return "尚未请求权限"
        @unknown default:
            return "未知状态"
        }
    }
    
    private func showGoToSettings(for status: PHAuthorizationStatus) -> Bool {
        return status == .denied || status == .restricted
    }
    
    private func showGoToSettings(for status: AVAuthorizationStatus) -> Bool {
        return status == .denied || status == .restricted
    }
    
    private func statusLabel(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "已开启"
        case .limited: return "受限"
        case .notDetermined: return "未请求"
        default: return "未开启"
        }
    }
    
    private func statusLabel(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "已开启"
        case .notDetermined: return "未请求"
        default: return "未开启"
        }
    }
}

#Preview {
    NavigationStack {
        PrivacySettingsView()
            .environment(ThemeManager())
    }
}
