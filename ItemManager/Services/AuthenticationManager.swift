//
//  AuthenticationManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/28/26.
//

import Foundation
import AuthenticationServices
import SwiftUI
import Combine

@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    static let shared = AuthenticationManager()
    
    @AppStorage("userIdentifier") var userIdentifier: String = ""
    @AppStorage("userGivenName") var givenName: String = ""
    @AppStorage("userFamilyName") var familyName: String = ""
    @AppStorage("userEmail") var email: String = ""
    
    // 缓存用户信息，用于在 Apple 不返回姓名时（非首次登录）恢复数据
    @AppStorage("cachedUserIdentifier") private var cachedUserIdentifier: String = ""
    @AppStorage("cachedGivenName") private var cachedGivenName: String = ""
    @AppStorage("cachedFamilyName") private var cachedFamilyName: String = ""
    @AppStorage("cachedEmail") private var cachedEmail: String = ""
    
    // 自定义头像和昵称 - 按用户ID存储
    @AppStorage("customNickname") var customNickname: String = ""
    @AppStorage("customAvatarPath") var customAvatarPath: String = ""
    
    // 存储每个Apple ID对应的自定义资料 (格式: userID: {"nickname": "xxx", "avatarPath": "xxx"})
    @AppStorage("userProfiles") private var userProfilesData: String = "{}"
    
    @Published var isAuthenticated: Bool = false
    @Published var isLoggingIn: Bool = false
    @Published var errorMessage: String?
    
    // 当前用户的完整资料
    var currentUserProfile: UserProfile {
        get {
            loadUserProfile(for: userIdentifier)
        }
        set {
            saveUserProfile(newValue, for: userIdentifier)
        }
    }
    
    // 显示用的昵称（优先使用自定义昵称）
    var displayName: String {
        if !customNickname.isEmpty {
            return customNickname
        }
        if !givenName.isEmpty {
            return givenName
        }
        return "已登录用户"
    }
    
    // 是否有自定义头像
    var hasCustomAvatar: Bool {
        !customAvatarPath.isEmpty && FileManager.default.fileExists(atPath: avatarFileURL.path)
    }
    
    // 获取头像文件的完整 URL（动态构建，避免绝对路径失效）
    var avatarFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let avatarDir = documentsPath.appendingPathComponent("UserAvatars", isDirectory: true)
        return avatarDir.appendingPathComponent(customAvatarPath)
    }
    
    override private init() {
        super.init()
        checkCredentialState()
        loadCurrentUserProfile()
    }
    
    // MARK: - 用户资料管理
    
    struct UserProfile: Codable {
        var nickname: String = ""
        var avatarPath: String = ""
        var updatedAt: Date = Date()
    }
    
    // 公开方法供 BackupService 使用
     func loadUserProfile(for userID: String) -> UserProfile {
         guard !userID.isEmpty else { return UserProfile() }
         
         if let data = userProfilesData.data(using: .utf8),
            let profiles = try? JSONDecoder().decode([String: UserProfile].self, from: data),
            let profile = profiles[userID] {
             return profile
         }
         return UserProfile()
     }
     
     func saveUserProfile(_ profile: UserProfile, for userID: String) {
         guard !userID.isEmpty else { return }
         
         var profiles: [String: UserProfile] = [:]
         if let data = userProfilesData.data(using: .utf8),
            let existing = try? JSONDecoder().decode([String: UserProfile].self, from: data) {
             profiles = existing
         }
         
         profiles[userID] = profile
         
         if let data = try? JSONEncoder().encode(profiles),
            let json = String(data: data, encoding: .utf8) {
             userProfilesData = json
         }
         
         // 同步到当前属性
         if userID == self.userIdentifier {
             customNickname = profile.nickname
             customAvatarPath = profile.avatarPath
         }
     }
    
    func loadCurrentUserProfile() {
        let profile = loadUserProfile(for: userIdentifier)
        customNickname = profile.nickname
        customAvatarPath = profile.avatarPath
    }
    
    func updateCustomNickname(_ nickname: String) {
        var profile = currentUserProfile
        profile.nickname = nickname
        profile.updatedAt = Date()
        currentUserProfile = profile
        customNickname = nickname
    }
    
    func updateCustomAvatar(image: UIImage) {
        guard !userIdentifier.isEmpty else { return }
        
        // 保存头像到应用沙盒
        let filename = "avatar_\(userIdentifier.suffix(8))_\(Int(Date().timeIntervalSince1970)).jpg"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let avatarDir = documentsPath.appendingPathComponent("UserAvatars", isDirectory: true)
        
        // 创建目录
        try? FileManager.default.createDirectory(at: avatarDir, withIntermediateDirectories: true)
        
        let fileURL = avatarDir.appendingPathComponent(filename)
        
        // 压缩并保存图片
        if let data = image.jpegData(compressionQuality: 0.8) {
            do {
                try data.write(to: fileURL)
                
                // 删除旧头像
                if !customAvatarPath.isEmpty {
                    let oldFileURL = avatarDir.appendingPathComponent(customAvatarPath)
                    if oldFileURL.path != fileURL.path {
                        try? FileManager.default.removeItem(at: oldFileURL)
                    }
                }
                
                var profile = currentUserProfile
                profile.avatarPath = filename  // 只存储文件名，不是完整路径
                profile.updatedAt = Date()
                currentUserProfile = profile
                customAvatarPath = filename  // 只存储文件名
                
                AppLogger.info("头像已保存到: \(fileURL.path)")
            } catch {
                AppLogger.error("保存头像失败: \(error)")
            }
        }
    }
    
    func clearCustomAvatar() {
        if !customAvatarPath.isEmpty {
            let fileURL = avatarFileURL
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        var profile = currentUserProfile
        profile.avatarPath = ""
        profile.updatedAt = Date()
        currentUserProfile = profile
        customAvatarPath = ""
    }
    
    // 检查用户的 Apple ID 凭证状态
    func checkCredentialState() {
        // 清除之前的错误信息
        errorMessage = nil
        
        guard !userIdentifier.isEmpty else {
            isAuthenticated = false
            return
        }
        
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userIdentifier) { [weak self] state, error in
            DispatchQueue.main.async {
                switch state {
                case .authorized:
                    self?.isAuthenticated = true
                case .revoked, .notFound, .transferred:
                    self?.isAuthenticated = false
                    // 可选：如果需要，可以在此处清除存储的数据，但在重新登录场景下保留数据可能更好
                @unknown default:
                    self?.isAuthenticated = false
                }
            }
        }
    }
    
    func signOut() {
        userIdentifier = ""
        givenName = ""
        familyName = ""
        email = ""
        customNickname = ""
        customAvatarPath = ""
        isAuthenticated = false
        errorMessage = nil
    }
    
    // MARK: - 登录流程
    
    func handleSignIn(result: Result<ASAuthorization, Error>) {
        // 重置错误信息
        errorMessage = nil
        isLoggingIn = true
        
        switch result {
        case .success(let authorization):
            handleAuthorization(authorization)
        case .failure(let error):
            isLoggingIn = false
            // 处理错误，忽略用户取消的情况
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                AppLogger.info("用户取消了登录")
                return
            }
            
            self.errorMessage = "登录失败: \(error.localizedDescription)"
            AppLogger.error("登录失败: \(error.localizedDescription)")
        }
    }
    
    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            self.isLoggingIn = false
            self.errorMessage = "登录失败: 无效的凭证"
            return
        }
        
        let userId = appleIDCredential.user
        
        // 获取 Identity Token 用于后端验证
        guard let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            self.isLoggingIn = false
            self.errorMessage = "登录失败: 无法获取身份令牌"
            return
        }
        
        Task {
            do {
                // 执行网络验证
                try await verifyUserWithBackend(identityToken: identityToken, userIdentifier: userId)
                
                // 验证成功，保存用户信息
                await MainActor.run {
                    self.saveUserInfo(credential: appleIDCredential)
                    self.isAuthenticated = true
                    self.isLoggingIn = false
                    self.loadCurrentUserProfile() // 加载该用户的自定义资料
                    AppLogger.info("登录成功: \(userId)")
                }
            } catch {
                await MainActor.run {
                    self.isLoggingIn = false
                    self.errorMessage = "登录验证失败: \(error.localizedDescription)"
                    AppLogger.error("登录验证失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func saveUserInfo(credential: ASAuthorizationAppleIDCredential) {
        let userId = credential.user
        self.userIdentifier = userId
        
        // 姓名和电子邮件仅在第一次登录时返回。
        // 我们应该将它们持久化保存。
        if let name = credential.fullName {
            if let given = name.givenName {
                self.givenName = given
                self.cachedGivenName = given
            }
            if let family = name.familyName {
                self.familyName = family
                self.cachedFamilyName = family
            }
        } else if userId == self.cachedUserIdentifier {
            // 如果是同一个用户且 Apple 没返回名字，尝试从缓存恢复
            if self.givenName.isEmpty { self.givenName = self.cachedGivenName }
            if self.familyName.isEmpty { self.familyName = self.cachedFamilyName }
        }
        
        if let email = credential.email {
            self.email = email
            self.cachedEmail = email
        } else if userId == self.cachedUserIdentifier {
            // 尝试从缓存恢复邮箱
            if self.email.isEmpty { self.email = self.cachedEmail }
        }
        
        // 更新缓存的 ID
        self.cachedUserIdentifier = userId
    }
    
    // 模拟后端验证接口
    private func verifyUserWithBackend(identityToken: String, userIdentifier: String) async throws {
        // 模拟网络延迟
        try await Task.sleep(nanoseconds: 1 * 1_000_000_000) // 1秒
        
        // 模拟验证逻辑
        // 在实际项目中，这里应该发送 HTTP 请求将 identityToken 发送给后端
        // 后端验证 token 的签名和有效期
        
        AppLogger.info("模拟后端验证成功: Token长度 \(identityToken.count)")
        
        // 如果验证失败，抛出错误
        // throw NSError(domain: "AuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "后端验证失败"])
    }

}
